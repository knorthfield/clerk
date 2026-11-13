<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="Clerk icon">
</p>

# Clerk

A meeting note taker and coach for the macOS menu bar. It works with all online meeting apps
(Zoom, Teams, Meet, FaceTime and others), because it records the sound of your Mac, not the
meeting app.

- **Prepare.** In **Meeting Prep**, add the participants, the agenda, your talking points and
  your notes. Use **Template** to copy a blank prep template, fill it in yourself or give it to an
  AI assistant, then paste it back.
- **Meet.** A floating panel shows under your camera, so you look at the camera when you read it.
  The left half shows the live transcript. The right half shows your talking points: the open
  ones at the top, and the ones you covered ticked below. People do not see the panel when you
  share your screen.
- **Get the notes.** When you stop, Clerk writes one markdown file: summary, decisions, action
  items, talking points, agenda, prep notes and the full transcript with a speaker for each turn.
  Then you pick who each speaker was from your participants.

Everything runs on your Mac. Your meetings do not go to the internet.

- Speech recognition: Parakeet TDT 0.6B v3 through FluidAudio (25 European languages). Clerk
  downloads the model (about 480 MB) the first time it starts.
- Speaker separation: pyannote community-1 through FluidAudio. Your microphone is always "Me".
  The other people are "Speaker 1", "Speaker 2"… until you name them.
- Summary, action items and automatic ticks: Apple Intelligence (the on-device Foundation Models).
  Without Apple Intelligence, Clerk still writes the transcript, and you tick points by hand.

## Use

1. Click the icon in the menu bar, then **Meeting Prep…**. Fill in the boxes.
2. Click **Start Meeting** when the meeting starts. The first time, macOS asks for access to the
   microphone and to system audio recording. Allow both.
3. Click a talking point to tick or untick it yourself.
4. Click **Stop** in the panel (or **Stop Meeting** in the menu). After a short time the notes open.

The notes go to `~/Documents/Clerk`. Change the folder in **Settings…**. The audio of each meeting
stays in `~/Library/Application Support/Clerk/<date and time>/` (`me.caf` and `others.caf`).

Use headphones if you can. With speakers, your microphone also hears the other people.

## Build

Needs macOS 26, Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
echo 'DEVELOPMENT_TEAM = <your team ID>' > Local.xcconfig
xcodegen generate
open Clerk.xcodeproj
```

`./test.sh` generates the project and runs the tests.
