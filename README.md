# Commentary Boost

Turns the cars down and the commentators up for anything playing on this Mac (F1 TV in a
browser, the TV app, YouTube, etc.). It uses Apple's built-in voice isolation, the same engine
as FaceTime/Final Cut "Voice Isolation", so there's nothing extra to install.

## Run it

Build once (or after changing the code):

```bash
swift build -c release
```

Then start it **from the Terminal app** while the race is playing:

```bash
.build/release/commentary-boost
```

### One-time permissions

macOS doesn't prompt for system-audio access when you run a command-line tool, so add it
yourself:

1. **System Settings → Privacy & Security → Screen & System Audio Recording**
2. Under **System Audio Recording Only**, click **+** and add **Terminal**
3. Quit and reopen Terminal

Until that's done, the tool shows "waiting for audio… (your sound is unchanged)" and leaves
your Mac's sound alone. Once real audio arrives, it mutes the original and plays the boosted
version.

For **play/pause from your phone**, Terminal also needs **Accessibility** permission. macOS
asks for this the first time you start the tool. If you missed it, go to
**System Settings → Privacy & Security → Accessibility** and turn on Terminal.

| Key       | Does                                                            |
| --------- | --------------------------------------------------------------- |
| ↑ / ↓     | More / less car sound, in 5% steps (`+` / `-` work too)          |
| b         | Bypass: hear the original sound, to compare                      |
| m         | Switch isolation model (Voice / High Quality Voice)              |
| q         | Quit (Ctrl-C also works); your Mac's audio goes back to normal   |

Options: `--cars 10` sets the starting car level (default 20%), `--hq` starts in High
Quality Voice mode, `--port 9000` changes the phone remote's port (default 8737), and
`--no-remote` turns the remote off.

## Phone remote

When it starts, the tool prints a QR code in Terminal. Scan it with your phone's camera; the
phone and Mac need to be on the same Wi-Fi. In Safari, use **Share → Add to Home Screen** so it
opens full screen like an app. The address and access code stay the same between runs, so the
home-screen icon keeps working.

From the phone you can:

- Drag the **car sound** slider, or tap a preset (0 / 10 / 20 / 40%)
- **Play / Pause** whatever video is playing, even full screen (it sends the ⏯ media key)
- **Back / Forward** (the arrow icons): press ← or → in the front window to jump a few seconds
- **Compare original**, or switch the **voice model**

Quit from the Mac with **q** in Terminal.

The link contains a random access code, so other people on your Wi-Fi can't control it
without scanning the QR code. To reset the code, delete
`~/Library/Application Support/CommentaryBoost/remote-token`.

## What it does

1. A system-audio tap captures everything the Mac plays and, once audio is arriving, mutes
   the original.
2. **Leveler:** a compressor squashes sudden loud moments (starts, crashes, onboard shots).
3. **Voice isolation:** separates the voices, then blends back the chosen percentage of the
   original sound so you still get some race atmosphere.
4. **Limiter:** restores the volume and prevents clipping.

In testing on synthetic commentary over V6 engine noise, the original audio had the engines
1.6 dB *louder* than the voice. With the default 20% setting the engines sit about 8 dB
*below* the voice, at 0% they're effectively gone, and the commentary stays at its original
loudness.

## Good to know

- It adds about 85 ms of audio delay. That's unnoticeable with race footage but slightly
  visible on talking-heads shots.
- It plays to whatever output was selected when it started. If you switch to headphones or
  AirPods, restart it.
- Team radio and crowd noise also pass through the isolation, which may sound a bit
  processed.
- To create a new file from a recording: `commentary-boost process in.wav out.wav --cars 15`

