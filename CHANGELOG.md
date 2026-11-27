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

## Unreleased

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
