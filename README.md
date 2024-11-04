# fancy-cat
A (blazingly-fast) PDF viewer for terminals using the Kitty image protocol (written in Zig).
![demo](https://github.com/user-attachments/assets/32393f0a-2cc3-438d-8c4e-870317714c2a)[^1]
[^1]: This demo shows me editing a Typst file that automatically compiles with each change, prompting fancy-cat to re-render whenever the PDF updates.
> [!NOTE]  
> This project is under active development
## Instructions
### Requirements
- Terminal emulator with the Kitty image protocol (e.g. Kitty, WezTerm, Konsole, etc.)
- [mupdf](https://mupdf.readthedocs.io/en/latest/quick-start-guide.html)
- Zig
### Build
> [!IMPORTANT]
> At the moment there is no dependency manager, so you will need to manually install the requirements.
```
zig build run -- <path-to-pdf> <optional-page-number>
```
## Features
- [x] Filewatch
- [x] Navigate pages
- [ ] Zoom
- [ ] Ghostty support
