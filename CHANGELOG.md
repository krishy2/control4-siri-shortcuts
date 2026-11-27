# <span style="color:#660066">Changelog</span>

<!--
Template for a new release entry (copy below the heading, fill in, uncomment):

## v[Version] - YYYY-MM-DD

### Added
- Added

### Fixed
- Fixed

### Changed
- Changed

### Removed
- Removed
-->

## v2026112703 - 2026-11-27

### Fixed

- Siri Shortcuts: commands from the shortcut were "unreadable". Shortcuts posts
  the Use Model response as a rich text (RTF) file; the driver now reads the
  dictionary inside it. Chunked uploads, `Expect: 100-continue` and form fields
  are read too.

### Changed

- Siri Shortcuts: an unreadable command shows its size and content type in Last
  Command and the log; Debug logging shows each request's size and type, Trace
  its body.

## v2026112702 - 2026-11-27

### Added

- Siri Shortcuts: voice control from iPhone, iPad and Apple Watch with one Apple
  Shortcut and no extra hardware. The controller serves the project's rooms,
  lights, Advanced Lighting scenes, scenarios (custom buttons and macros) and
  room sources to the shortcut (`GET /context`); Apple's Shortcuts **Use Model**
  action turns the spoken request into a command, which the driver carries out
  (`POST /execute`) and answers with a sentence for Siri to speak. Lights on,
  off and to a level, scenes on and off, scenarios, room sources, volume, mute,
  play, pause, tracks and room off. Test mode (Execute Commands: No), Hidden
  Names, Extra Instructions, Default Room.
