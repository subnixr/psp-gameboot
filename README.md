# psp-gameboot

Build a PSP `gameboot.pmf` from any video (plus optional audio) with one command.

It replicates the [wololo.net gameboot tutorial](https://wololo.net/talk/viewtopic.php?t=38029) without the GUI tools: `ffmpeg` replaces VirtualDub, WinMEnc and the WAV converter, and the Sony PSMF command-line tools run under `wine`.

## Requirements

- `ffmpeg` and `ffprobe`
- `wine`
- First run only: `curl`, `sha256sum` or `shasum`, and one of `7z`, `7zz`, `7za`, `bsdtar`

## Usage

```
psp-gameboot.sh [-t seconds] [-b video_kbps] [-a audio_kbps] [-o out.pmf] [-k] [-y] [video] [audio]
```

```sh
# The only .mov in the current directory, with ./gameboot.wav as audio if present
./psp-gameboot.sh

# Trim to 2.5 seconds, as the tutorial does
./psp-gameboot.sh -t 2.5 intro.mp4

# Custom bitrates, output path and a separate audio file
./psp-gameboot.sh -b 1500 -a 96 -o out/gameboot.pmf clip.mkv music.wav
```

| Option  | Meaning                                                              | Default                                              |
| ------- | -------------------------------------------------------------------- | ---------------------------------------------------- |
| `-t`    | Trim to this many seconds                                            | keep full length                                     |
| `-b`    | Average video bitrate in kbps, 1000-2000 (peak is twice this)        | `2000`                                               |
| `-a`    | Audio bitrate in kbps: 48, 64, 96, 128, 160, 192, 256 or 320         | `128`                                                |
| `-o`    | Output file                                                          | `./gameboot.pmf`                                     |
| `-k`    | Keep the temp build dir and print its path                           | removed on exit                                      |
| `-y`    | Download the PSMF suite without asking                               | ask first                                            |
| `video` | Source video                                                         | the only `.mov` in the current directory             |
| `audio` | Source audio                                                         | `./gameboot.wav` if present, else the video's audio  |

## How it works

1. `ffmpeg` scales the video to 480x272 at 29.97 fps and writes a raw AVI. A source with alpha is flattened onto black.
2. `ffmpeg` converts the audio to 44.1 kHz 16-bit stereo WAV.
3. `psmfenc` encodes the video to H.264 (two passes) and the audio to ATRAC3plus.
4. `psmfmux` muxes both into an MPEG2 program stream.
5. `PsmfComposerCMD` adds the PSMF header.
6. The header version is patched from `PSMF0015` to `PSMF0012`, because the XMB only plays gameboots with the old header.

## The PSMF suite

Steps 3 to 5 use the Sony PSMF Stream Composer Suite, a set of third-party Windows binaries that this repository does not ship. On first run the script asks before downloading it (about 10 MB), checks its SHA-256, and unpacks it to `${XDG_CACHE_HOME:-~/.cache}/psp-gameboot/psmf`. Pass `-y` to skip the prompt, which is required when stdin is not a terminal.

Scratch files go to a temp dir on wine's `C:` drive, removed on exit unless `-k` is given.

## Installing on the PSP

See the [tutorial](https://wololo.net/talk/viewtopic.php?t=38029) for how to put the resulting `gameboot.pmf` on the console.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
