# fancy-cat
A PDF viewer for terminals using the Kitty image protocol.
![demo](https://github.com/user-attachments/assets/b1edc9d2-3b1f-437d-9b48-c196d22fcbbd) [^1]
[^1]: This demo shows me editing a Typst file that automatically compiles with each change, prompting fancy-cat to re-render whenever the PDF updates.
> [!NOTE]  
> This project is under active development
## Usage
The keymappings and other options can be found and changed in the config file [here](./src/config.zig).
## Build Instructions
### Requirements
- Terminal emulator with the Kitty image protocol (e.g. Kitty, WezTerm, Konsole, etc.)
- [mupdf](https://mupdf.readthedocs.io/en/latest/quick-start-guide.html)
#### MacOS
``` sh
brew install mupdf
```
#### Linux
``` sh
apt install \
    libmupdf-dev \
    libharfbuzz-dev \
    libfreetype6-dev \
    libjbig2dec0-dev \
    libjpeg-dev \
    libopenjp2-7-dev \
    libgumbo-dev \
    libmujs-dev \
    zlib1g-dev
```
### Build
```sh
zig build --fetch
```
### Run
```
zig build run -- <path-to-pdf> <optional-page-number>
```
## Features
- [x] Filewatch
- [x] Navigate pages
- [x] Double buffering
- [x] MacOS support
- [x] Linux support
- [x] Dark-mode
- [ ] Zoom
- [ ] Ghostty support
- [ ] Cache
- [ ] Status bar
- [ ] Synctex
