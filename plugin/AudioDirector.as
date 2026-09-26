class AudioDirector {
    Audio::Sample@ jumpChime;
    Audio::Sample@ failureChime;
    Audio::Sample@ resultsMusic;
    Audio::Sample@ previewSample;
    Audio::Voice@ cueVoice;
    Audio::Voice@ resultVoice;
    Audio::Voice@ finishVoice;
    Audio::Voice@ previewVoice;
    bool finishPlayed = false;
    bool loopResults = false;
    int64 finishStartedAt = -1;
    int64 rewindRequestedAt = -1;
    float cueBaseGain = 0.0f;
    float resultBaseGain = 0.0f;
    float previewBaseGain = 0.0f;
    string previewStatus = "";

    Audio::Sample@ LoadLocal(const string &in filename, bool streamed = false) {
        if (filename.Length == 0) return null;
        if (filename.Contains("..") || filename.Contains("|") ||
            filename.Contains("/") || filename.Contains("\\") ||
            filename.Contains(":")) {
            print("Gorilla Grip Trainer audio file name rejected: " + filename);
            return null;
        }
        string path = IO::FromStorageFolder("LocalSounds/" + filename);
        if (!IO::FileExists(path)) {
            print("Gorilla Grip Trainer audio missing: " + filename);
            return null;
        }
        Audio::Sample@ sample = Audio::LoadSampleFromAbsolutePath(path, streamed);
        if (sample is null)
            print("Gorilla Grip Trainer audio could not load: " + filename);
        return sample;
    }

    void Load() {
        InitVoicePools();
        StopTransient();
        StopPreview();
        @jumpChime = LoadLocal(S_JumpFile);
        @failureChime = LoadLocal(S_FailureFile);
        // Buffered, not streamed: a streamed sample supports only one voice,
        // so looping (a second Play or a rewind) fails once its voice ends.
        @resultsMusic = LoadLocal(S_ResultsFile);
        for (uint i = 0; i < g_voicePools.Length; i++) {
            VoicePool@ pool = g_voicePools[i];
            pool.lastPick = -1;
            for (uint j = 0; j < pool.entries.Length; j++)
                @pool.entries[j].sample = LoadLocal(pool.entries[j].file);
        }
    }

    void Mute(Audio::Voice@ voice) {
        if (voice !is null) voice.SetGain(0.0f);
    }

    void StopTransient() {
        Mute(cueVoice);
        Mute(resultVoice);
        @cueVoice = null;
        @resultVoice = null;
    }

    void OnReset() {
        StopTransient();
        StopResults();
        StopPreview();
        finishPlayed = false;
    }

    void StopPreview() {
        Mute(previewVoice);
        @previewVoice = null;
        @previewSample = null;
        previewStatus = "";
    }

    void PreviewFile(const string &in filename, float gain) {
        StopPreview();
        @previewSample = LoadLocal(filename);
        if (previewSample is null) {
            previewStatus = filename.Length == 0 ? "Choose a clip first" :
                "Could not preview " + filename;
            return;
        }
        previewBaseGain = Math::Clamp(gain, 0.0f, 1.0f);
        @previewVoice = Audio::Play(previewSample,
            previewBaseGain * S_MasterVolume);
        previewStatus = previewVoice is null ? "Could not play " + filename : "";
        if (previewVoice !is null)
            print("Gorilla Grip Trainer audio: preview " + filename +
                " gain " + Text::Format("%.2f", previewVoice.GetGain()));
    }

    void StopResults() {
        Mute(finishVoice);
        @finishVoice = null;
        loopResults = false;
        finishStartedAt = -1;
        rewindRequestedAt = -1;
    }

    void UpdateSettings() {
        if (previewVoice !is null)
            previewVoice.SetGain(previewBaseGain * S_MasterVolume);
        if (!S_EnableAudio) {
            StopTransient();
            StopResults();
            return;
        }
        if (cueVoice !is null) cueVoice.SetGain(cueBaseGain * S_MasterVolume);
        if (resultVoice !is null)
            resultVoice.SetGain(resultBaseGain * S_MasterVolume);
        if (!S_SoundResults) StopResults();
        if (finishVoice is null) return;
        finishVoice.SetGain(S_ResultsVolume * S_MasterVolume);
        if (!loopResults || finishStartedAt < 0) return;
        double length = finishVoice.GetLength();
        if (length <= 0.1 ||
            Time::MilliStamp - finishStartedAt < int64(length * 1000.0 - 20.0))
            return;
        // Preferred: start a fresh voice (buffered samples allow many voices).
        Audio::Voice@ next = resultsMusic is null ? null :
            Audio::Play(resultsMusic, S_ResultsVolume * S_MasterVolume);
        if (next is null && rewindRequestedAt < 0) {
            // Fallback: rewind the existing voice once before giving up.
            finishVoice.SetPosition(0.0);
            rewindRequestedAt = Time::MilliStamp;
            finishStartedAt = Time::MilliStamp;
            print("Gorilla Grip Trainer audio: results loop restarted via rewind");
            return;
        }
        if (next is null) {
            loopResults = false;
            print("Gorilla Grip Trainer audio: results loop could not restart");
            return;
        }
        Mute(finishVoice);
        @finishVoice = next;
        rewindRequestedAt = -1;
        finishStartedAt = Time::MilliStamp;
        print("Gorilla Grip Trainer audio: results loop started");
    }

    void OnTakeoffCue() {
        if (!S_EnableAudio || !S_SoundTakeoff || jumpChime is null) return;
        Mute(cueVoice);
        cueBaseGain = S_JumpVolume;
        @cueVoice = Audio::Play(jumpChime,
            cueBaseGain * S_MasterVolume);
        print("Gorilla Grip Trainer audio: jump cue");
    }

    bool GradeVoiceEnabled(const string &in grade) {
        if (grade == "S") return S_GradeSEnabled;
        if (grade == "A") return S_GradeAEnabled;
        if (grade == "B") return S_GradeBEnabled;
        if (grade == "C") return S_GradeCEnabled;
        if (grade == "D") return S_GradeDEnabled;
        return false;
    }

    VoiceEntry@ PickVoice(VoicePool@ pool) {
        if (pool is null) return null;
        array<int> valid;
        for (uint i = 0; i < pool.entries.Length; i++)
            if (pool.entries[i].sample !is null) valid.InsertLast(int(i));
        if (valid.Length == 0) return null;
        int count = int(valid.Length);
        int pick = Math::Rand(0, count);
        if (count > 1 && valid[pick] == pool.lastPick)
            pick = (pick + 1 + Math::Rand(0, count - 1)) % count;
        pool.lastPick = valid[pick];
        return pool.entries[valid[pick]];
    }

    void OnVerdict(JumpVerdict@ verdict) {
        if (verdict is null) return;
        Mute(cueVoice);
        @cueVoice = null;
        Mute(resultVoice);
        @resultVoice = null;
        if (!S_EnableAudio) return;
        if (verdict.label == "MISSED") {
            if (S_SoundFailure && failureChime !is null) {
                resultBaseGain = S_FailureVolume;
                @resultVoice = Audio::Play(failureChime,
                    resultBaseGain * S_MasterVolume);
            }
            print("Gorilla Grip Trainer audio: failed landing");
            return;
        }
        if (verdict.label == "UNRATED") return;
        if (S_SoundVoices && GradeVoiceEnabled(verdict.label)) {
            VoiceEntry@ entry = PickVoice(VoicePoolFor(verdict.label));
            if (entry !is null) {
                resultBaseGain = entry.volume;
                @resultVoice = Audio::Play(entry.sample,
                    resultBaseGain * S_MasterVolume);
                print("Gorilla Grip Trainer audio: landing " + verdict.label +
                    " -> " + entry.file);
            }
        }
    }

    void PlayResults(bool loop = false) {
        StopResults();
        if (!S_EnableAudio || !S_SoundResults) {
            print("Gorilla Grip Trainer audio: results disabled");
            return;
        }
        if (resultsMusic is null) {
            print("Gorilla Grip Trainer audio: results file unavailable");
            return;
        }
        @finishVoice = Audio::Play(resultsMusic,
            S_ResultsVolume * S_MasterVolume);
        if (finishVoice is null) {
            print("Gorilla Grip Trainer audio: results voice could not start");
            return;
        }
        loopResults = loop;
        finishStartedAt = Time::MilliStamp;
        print("Gorilla Grip Trainer audio: results voice started, length " +
            Text::Format("%.2f", finishVoice.GetLength()) + "s, gain " +
            Text::Format("%.2f", finishVoice.GetGain()));
    }

    void OnFinish() {
        if (finishPlayed) return;
        finishPlayed = true;
        StopTransient();
        StopPreview();
        PlayResults(true);
    }
}
