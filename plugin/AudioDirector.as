class AudioDirector {
    Audio::Voice@ cueVoice;
    Audio::Voice@ resultVoice;
    Audio::Voice@ finishVoice;
    Audio::Voice@ previewVoice;
    Cue previewCue = Cue::Takeoff;
    bool finishPlayed = false;
    bool loopResults = false;
    int64 finishStartedAt = -1;
    string previewStatus = "";

    void Load() {
        StopTransient();
        StopPreview();
        LoadSoundCues();
    }

    float Gain(Cue cue) {
        return CueVolume(cue) * S_MasterVolume;
    }

    Audio::Voice@ Play(Cue cue) {
        Audio::Sample@ sample = g_soundCues[uint(cue)].Pick();
        if (sample is null) return null;
        return Audio::Play(sample, Gain(cue));
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

    // A new attempt; a settings preview keeps playing.
    void OnReset() {
        StopTransient();
        StopResults();
        finishPlayed = false;
    }

    void StopPreview() {
        Mute(previewVoice);
        @previewVoice = null;
        previewStatus = "";
    }

    void PreviewCue(Cue cue) {
        StopPreview();
        previewCue = cue;
        @previewVoice = Play(cue);
        if (previewVoice is null)
            previewStatus = "No sound files in LocalSounds/" + g_cueFolders[uint(cue)];
    }

    void StopResults() {
        Mute(finishVoice);
        @finishVoice = null;
        loopResults = false;
        finishStartedAt = -1;
    }

    // Follows the volume settings and restarts the finish music when it ends.
    // The short takeoff and landing sounds keep the volume they started with.
    void UpdateSettings() {
        if (previewVoice !is null) previewVoice.SetGain(Gain(previewCue));
        if (!S_EnableAudio) {
            StopTransient();
            StopResults();
            return;
        }
        if (!S_SoundFinish) StopResults();
        if (finishVoice is null) return;
        finishVoice.SetGain(Gain(Cue::Finish));
        if (!loopResults || finishStartedAt < 0) return;
        double length = finishVoice.GetLength();
        if (length <= 0.1 ||
            Time::MilliStamp - finishStartedAt < int64(length * 1000.0 - 20.0))
            return;
        // Each loop picks a new file.
        Audio::Voice@ next = Play(Cue::Finish);
        if (next is null) {
            loopResults = false;
            warn("Audio: the finish music could not restart");
            return;
        }
        Mute(finishVoice);
        @finishVoice = next;
        finishStartedAt = Time::MilliStamp;
        DebugLog("Audio: finish music loop started");
    }

    void OnTakeoffCue() {
        if (!S_EnableAudio || !S_SoundTakeoff) return;
        Mute(cueVoice);
        @cueVoice = Play(Cue::Takeoff);
        DebugLog("Audio: takeoff");
    }

    void OnVerdict(JumpVerdict@ verdict) {
        if (verdict is null) return;
        StopTransient();
        Cue cue;
        if (!S_EnableAudio || !GradeCue(verdict.grade, cue) || !CueEnabled(cue)) return;
        @resultVoice = Play(cue);
        DebugLog("Audio: landing " + GradeName(verdict.grade));
    }

    void OnFinish() {
        if (finishPlayed) return;
        finishPlayed = true;
        StopTransient();
        StopPreview();
        StopResults();
        if (!S_EnableAudio || !S_SoundFinish) return;
        @finishVoice = Play(Cue::Finish);
        if (finishVoice is null) {
            DebugLog("Audio: no finish music in LocalSounds/" + g_cueFolders[uint(Cue::Finish)]);
            return;
        }
        loopResults = true;
        finishStartedAt = Time::MilliStamp;
        DebugLog("Audio: finish music started, length " +
            Text::Format("%.2f", finishVoice.GetLength()) + "s");
    }
}
