# ztor-encoding

The Ztor encoder. It turns a film's uploaded master into everything the platform streams: the H.264 renditions (2160p down to 360p), the DRM-protected HLS version and the clear watch-party version. It runs in Docker on your own machine, takes queued films from the platform at `https://video.ztor.stream`, and uploads the result itself. The master is read from the platform's storage, so the original file is not needed on this machine.

## What you need

- Docker Desktop (Windows, Mac) or Docker Engine (Linux), running
- Free disk of about three times the master's size (25 GB for a 6 GB master)
- Time: about 5 times the film's length for 1080p, more for 4K (a 95-minute film takes 6 to 8 hours)
- The runner token, sent to you separately. Never put it in a file in this repository or in a chat.

## Run it

Build the image, in this repository's folder:

```
docker build -t ztor-encoder .
```

Start the encoder (one line). It asks the platform every 10 seconds for the next queued film:

```
docker run -d --name ztor-runner -e POLL_URL=https://video.ztor.stream -e RUNNER_TOKEN=<token> -e RUNNER_NAME=cn-team-pc -e POLL_S=10 ztor-encoder
```

To keep the working files on a bigger drive, add `-e WORK_DIR=/work/tmp -v D:\ztor-work:/work/tmp` (Windows) or `-v /Volumes/Big/ztor-work:/work/tmp` (Mac).

Watch it:

```
docker logs -f ztor-runner
```

Expect `job <film id>`, the encode timing, `packaged`, `uploaded N files`, then `done -> 200`. A line with `FAILED` means the job stopped; send the log to the Ztor side.

Check a film in any browser: `https://video.ztor.stream/films/<FILM_ID>`. Its `status` goes `queued`, `encoding`, `packaged`, `ready`.

When nothing more is queued, stop the encoder:

```
docker rm -f ztor-runner
```

## Updating

When this repository changes, stop the runner, get the new files (`git pull`, or Code > Download ZIP), build the image again and start it again. A running container keeps the old version until it is rebuilt.

## Audio languages

A film can carry several audio languages, delivered inside the one master file: one stereo track per language, the default language first. Each track is tagged with its language from the Ztor table. The manifests and the Ztor app only ever see the Ztor code.

| Ztor code | Tag in an MP4 or MOV master | Language | Name for zh-tw / zh-hk | Name for en-us |
|---|---|---|---|---|
| `cn` | `cmn` | Mandarin | 國語 | Mandarin |
| `hk` | `yue` | Cantonese | 粵語 | Cantonese |
| `en` | `eng` | English | 英語 | English |
| `kr` | `kor` | Korean | 韓語 | Korean |
| `th` | `tha` | Thai | 泰語 | Thai |
| `de` | `deu` or `ger` | German | 德語 | German |
| `fr` | `fra` or `fre` | French | 法語 | French |
| `it` | `ita` | Italian | 義大利語 | Italian |
| `jp` | `jpn` | Japanese | 日語 | Japanese |

An MP4 or MOV file can only store a three-letter language tag, so MP4 and MOV masters use the second column; the encoder turns it into the Ztor code. An MKV master may carry the Ztor code itself.

- **Two or more tracks:** every track needs a different language from the table. An untagged track or another tag (for example `chi`) stops the job, and the log says which track.
- **One track:** never stops the job. A language from the table is kept; anything else plays as "Original".

Tag an MP4 master's tracks without re-encoding (Cantonese first, so it is the default):

```
ffmpeg -i master.mp4 -map 0:v -map 0:a -c copy -metadata:s:a:0 language=yue -metadata:s:a:1 language=cmn master_tagged.mp4
```

Check the tags before uploading. The encoder reads them the same way, one line per track:

```
ffprobe -v error -select_streams a -show_entries stream=index:stream_tags=language -of csv=p=0 master_tagged.mp4
```

## Files

| File | Job |
|---|---|
| `server.mjs` | Polls the platform for jobs, runs the steps below, uploads the result and reports back |
| `encode.sh` | One ffmpeg pass: the H.264 ladder and one AAC stereo file per audio language |
| `package.sh` | Shaka Packager: the DRM version, CMAF HLS encrypted with cbcs for Widevine, PlayReady and FairPlay |
| `package_clear.sh` | Shaka Packager: the clear watch-party version |
| `audio_codes.sh` | The Ztor audio language table, read by the three scripts |
| `Dockerfile` | Debian with ffmpeg, Shaka Packager and Node |

`.gitattributes` keeps Unix line endings on every machine. A script checked out with Windows line endings fails inside the container with `bash\r`.
