<!--
Kept deliberately SHORT. A template that asks for fifteen boxes gets the same
answers filled in mechanically, and the two that matter — "what does this
change" and "how did you verify it" — get one word.
-->

## What this changes

<!-- One or two sentences. A reviewer reading only this should know whether to
     care. If you cannot write two sentences, the change may be too big: split
     it. -->

Closes #

## Why

<!-- The problem, not the implementation. "Because the API kept drifting from
     the app" tells a future reader what to protect; "added a helper" does not. -->

## How it was verified

<!-- Paste the `hl check` / `hl test` result. "Tests pass" is not verification —
     it is a claim. If a gate is not applicable, say so and why. -->

```
python scripts/hl.py check
python scripts/hl.py test --scope <be|sk|cu>
```

## Checklist

- [ ] `python scripts/hl.py check` is green
- [ ] `python scripts/hl.py test` is green
- [ ] I added or updated a **test** that fails without this change
- [ ] Anything pre-existing that I fixed is in a **separate** commit
- [ ] No secret, key or `.env` value is in this diff
- [ ] New database changes come with a reversible migration
- [ ] User-facing strings go through `appText`, not literals

<!-- Anything you deliberately did NOT do, and why. This is the section that
     stops the next person assuming it was an oversight. -->

## Not done (and why)
