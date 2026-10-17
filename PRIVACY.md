# Privacy

Mantissa works out everything on your iPhone. It has no server, no account, no advertising and no analytics, and it asks for no
permission (no camera, photos, location, contacts or network).

## What is kept, and where

| What | Where | Why |
|---|---|---|
| The problems you have solved and their answers (the history, and the ones you saved) | A file in the app's own storage on your iPhone | So you can look at them again. |
| Your choices in Settings: angle unit, number of digits, language | The app's own defaults on your iPhone | So the app opens the way you left it. |

Nothing else is stored. Both are removed when you delete the app, and "Clear history" in the history screen removes the problems
(saved ones stay until you unsave or delete them).

## What is sent

Nothing. The app never opens a network connection, so there is nothing to send and nothing to receive. It contains no code from other
parties (see `THIRD_PARTY.md`), so there is no software development kit that could collect anything either.

## The App Privacy declaration

`App/Resources/PrivacyInfo.xcprivacy` declares that the app does not track you and collects no data, and gives the one reason it
reads the app's own defaults (to keep the settings above).

## Questions

Open an issue in the repository.
