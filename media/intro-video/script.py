# Hype cut: sections are laid out on a 130 BPM bar grid. Each section lists its voice lines:
# (key, subtitle text, tts text or None, voice, speed, beat offset from the previous line's end or section start)
BPM = 130
NARRATOR = ("am_michael", 1.1)
CUTE = ("af_bella", 0.9)

SECTIONS = [
    ("cold", 4, [("open", "200 km/h. Fully sideways.", "Two hundred kilometres an hour. Fully sideways.", NARRATOR, 8)]),
    ("problem", 4, [
        ("prob1", "You spin off the jump, land the other way… and your tires just give up.", "You spin off the jump, land the other way... and your tyres just, give up.", NARRATOR, 0),
        ("prob2", "400 milliseconds. Of nothing.", "Four hundred milliseconds. ... Of nothing.", NARRATOR, 1),
    ]),
    ("secret", 3, [("secret", "Here's the thing: the game remembers which way you're sliding, and only updates it while a wheel touches the ground.",
                    "Here's the thing. The game remembers which way you're sliding, and only updates it while a wheel touches the ground.", NARRATOR, 1)]),
    ("bullet", 4, [
        ("bt1", "So countersteer on the very last tick, while the last wheel is still on the lip…", "So, countersteer on the very last tick, while the last wheel is still on the lip...", NARRATOR, 0),
        ("bt2", "The timer burns off in the air, and you land with full grip.", "The timer burns off in the air, and you land, with full grip.", NARRATOR, 1),
    ]),
    ("gg", 2, [("gg", "That's the gorilla grip.", "That's, the gorilla grip.", NARRATOR, 0)]),
    ("catch", 3, [("catch", "Switch too early and you bleed speed: about a tenth of a km/h for every millisecond.",
                   "Switch too early, and you bleed speed. About a tenth of a kilometre per hour, for every millisecond.", NARRATOR, 0)]),
    ("build", 2, [("build", "So we built you a trainer.", None, NARRATOR, 0)]),
    ("reveal", 2, [("name", "Gorilla Grip Trainer.", "Gorilla. Grip. Trainer.", NARRATOR, 1)]),
    ("ingame", 4, [("ingame", "It reads the physics on every 10 ms tick and grades exactly how late you switched.",
                    "It reads the physics on every ten millisecond tick, and grades exactly how late you switched.", NARRATOR, 0)]),
    ("grades", 4, []),   # grade callouts are placed on beats, see GRADE_CALLS
    ("uwu", 3, [
        ("blush", "Land an S+ and even the gorilla blushes.", "Land an S plus, and even the gorilla blushes.", NARRATOR, 0),
        ("uwu", "uwu", "uwu.", CUTE, 2),
    ]),
    ("features", 4, [
        ("feat1", "Combos up to ×8. Three popup styles. Your own sounds. Every run saved.", "Combos up to times eight. Three popup styles. Your own sounds. Every run, saved.", NARRATOR, 0),
        ("feat2", "Any frame rate. Survives game updates.", None, NARRATOR, 1),
    ]),
    ("outro", 5, [
        ("out1", "Countersteer late. Land clean. Become the gorilla.", None, NARRATOR, 0),
        ("out2", "Gorilla Grip Trainer. Free on Openplanet.", "Gorilla Grip Trainer. Free, on Open Planet.", NARRATOR, 2),
    ]),
]
# grade callouts: (label, spoken, beat within the grades section)
GRADE_CALLS = [("S+", "S plus!", 0), ("S", "S!", 2), ("A", "A!", 4), ("B", "B!", 6), ("C", "C!", 8), ("D", "D!", 10), ("MISSED", "Missed.", 12)]
