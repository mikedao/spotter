"""
Katey: the announcer personality the shooter designed (2026-11-14), one question
at a time. A MEAN GIRL (the high-school queen bee, as in the movie Mean Girls -
in spirit only: no quotes or names from the film; was a flirty goth Instagram
girl until 2026-11-14) in Nicole's voice (af_nicole). A bit of the goth edge
stays mixed in (the shooter's call): wearing black, funerals, now and then -
not the main flavour.

She picks from a large bank of lines: katey_seed.txt (lines the shooter
approved one by one, and the ones rejected, with why - the style guide) and
katey_bank/*.txt, one per line, "situation | line". The web app reads them
(PersonalityBank); the score and direction are the standard pieces, said first.

Her rules, for any line added:
  - deadpan and unimpressed by default, so warming up means something
  - VERY LIGHT flirting only
  - bad shots: mean-girl roasts and teasing; harsh and PERSONAL is fine AS LONG
    AS IT'S FUNNY (cutting, clever, specific); a plain insult with a swear was
    rejected; swearing sometimes
  - NEVER anything near suicide or self-harm, not even as a joke
  - NEVER the journal goal (565), pace or the gap to it
  - no pet names (a pet name after a comma made an odd pause), no time of day,
    no invented history ("we talked about this")
  - occasional REAL tips, for a right-handed shooter, only for a pattern the
    shots show (situation "tip <direction>")
  - says the engine's lines and the diagnostic flags her way; the range
    officer's commands stay standard
  - same in practice, matches and finals
  - lower case; letters, spaces and . , ' - only; each piece between commas and
    full stops is spoken alone; placeholders {n} {total} {shots} {avg} {best}

After editing the bank: `bin/rails voices:personality_list ID=katey`, then
`speak.py export --personality katey --voice af_nicole` (only new pieces render).
"""

VOICE = "af_nicole"
TITLE = "Katey"
DESCRIPTION = "Mean girl. Queen bee, unimpressed, roasts your bad shots. Swears."
