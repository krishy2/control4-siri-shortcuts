<!-- Copyright 2026 Control Pro (control-pro.co.uk). All rights reserved. -->

<style>
@media print {
   .noprint {
      visibility: hidden;
      display: none;
   }
   * {
        -webkit-print-color-adjust: exact;
        print-color-adjust: exact;
    }
}
</style>

<img alt="Control Pro" src="./images/header.png" width="400"/>

______________________________________________________________________

# <span style="color:#660066">Overview</span>

Siri Shortcuts driver by **Control Pro** -
[control-pro.co.uk](https://control-pro.co.uk)

> DISCLAIMER: This software is neither affiliated with nor endorsed by either
> Control4 or Apple.

The Siri Shortcuts driver lets you control the home by voice from an iPhone,
iPad or Apple Watch with one Apple Shortcut: lights, Advanced Lighting scenes,
scenarios (custom buttons and macros) and room media (sources, volume, mute,
play, pause, tracks, room off). It needs no extra hardware, no cloud service and
no Control4 subscription.

Apple's own AI does the understanding. The shortcut asks the driver for the
project's names, lets the Shortcuts **Use Model** action turn what you said into
a command, and sends that command back to the driver, which carries it out and
answers with a sentence for Siri to speak.

The shortcut contains nothing about your project: rename a light in Composer and
the next request already uses the new name.

# <span style="color:#660066">Index</span>

<div style="font-size: small">

- [System Requirements](#system-requirements)
- [Installer Setup](#installer-setup)
  - [Driver Installation](#driver-installation)
  - [The Shortcut](#the-shortcut)
  - [Driver Properties](#driver-properties)
  - [Commands](#commands)
  - [Actions](#actions)
  - [Programming](#programming)
  - [HTTP Endpoints](#http-endpoints)
  - [Updates](#updates)
- [Support](#support)
- [Changelog](#changelog)

</div>

# <span style="color:#660066">System Requirements</span>

- Control4 OS 3.3+
- iPhone or iPad with Apple Intelligence (iOS 26 or later) for the Use Model
  action
- The phone on the same network as the controller (or on a VPN to it)

# <span style="color:#660066">Installer Setup</span>

## Driver Installation

1. Add the **Siri Shortcuts** driver to the project (one per project is enough).
   Its room is the default room for media commands that name none.
1. Note the **Context URL** and **Execute URL** properties.
1. Build the shortcut below on each phone.

## The Shortcut

Create a new shortcut with a short name Siri hears well (e.g. "Home") and add
these actions:

1. **Get Contents of URL**: the Context URL (method GET).
1. **Dictate Text**: Stop Listening After Pause.
1. **Text**: the _Contents of URL_ variable, an empty line, then `Request: `
   followed by the _Dictated Text_ variable.
1. **Use Model**: model Cloud (Private Cloud Compute), input the Text from step
   3, Output **Dictionary**.
1. **Get Contents of URL**: the Execute URL, method **POST**, Request Body
   **File**, File = the _Response_ of step 4.
1. **Speak Text**: the _Contents of URL_ of step 5.

Say "Hey Siri, Home", then the request: "turn on the dining light", "living room
volume 30", "a bit quieter in the bedroom", "play Sonos in the kitchen", "run
Arrived".

If the Dictionary output gives trouble, set step 4's Output to **Text**; the
driver also reads the dictionary as JSON text.

## Driver Properties

### Update Settings

- **Automatic Updates** \[ Off | **_On_** \]: install new releases from GitHub
  by themselves, checked every 30 minutes.
- **Update Channel** \[ **_Production_** | Prerelease \]: Prerelease also
  installs test releases.

### Driver Settings

- **Driver Status** (read-only): whether the driver listens.
- **Driver Version** (read-only)
- **Log Level**, **Log Mode**: as in the other drivers of the suite.

### Shortcut Settings

- **Port** \[ 1024 - 65535, **_8765_** \]: HTTP port on the controller. There is
  no password: anything on the network can send commands.
- **Context URL**, **Execute URL** (read-only): the two addresses for the
  shortcut.
- **Execute Commands** \[ **_Yes_** | No \]: No is test mode. Commands are
  understood, logged and answered ("Test mode. Dining on."), but nothing is
  sent.
- **Default Room**: room for media commands that name none. None uses the
  driver's own room.
- **Volume Step** \[ 1 - 50, **_10_** \]: percent for "louder" and "quieter"
  without a number.
- **Hidden Names**: rooms, lights, scenes, scenarios and sources the shortcut
  should not know, comma separated; `*` is a wildcard.
- **Extra Instructions**: a sentence added to the AI's instructions, e.g.
  "Nappali means Living Room."

### Status

- **Known Names** (read-only): how many rooms, lights, scenes, scenarios and
  sources were found.
- **Last Request**, **Last Command**, **Last Reply**, **Last Sent** (read-only):
  the last call, the dictionary the shortcut sent, the answer and the Control4
  commands that went out.

## Commands

| Say                               | Action        | Control4                                   |
| --------------------------------- | ------------- | ------------------------------------------ |
| turn on / off the dining light    | light_on/off  | light ON / OFF                             |
| lights off in the kitchen         | light_off     | every light of the room OFF                |
| dining light to 40 percent        | light_level   | SET_BRIGHTNESS_TARGET                      |
| evening scene / evening scene off | scene         | Advanced Lighting ACTIVATE / DEACTIVATE    |
| run Arrived                       | scenario      | custom button SELECT / macro EXECUTE_MACRO |
| play Sonos in the living room     | source        | room SELECT_AUDIO / SELECT_VIDEO_DEVICE    |
| living room volume 30             | volume_set    | SET_VOLUME_LEVEL                           |
| a bit louder / quieter            | volume_up/dn  | SET_VOLUME_LEVEL from the room's volume    |
| mute, unmute, play, pause         | ...           | MUTE_ON, MUTE_OFF, PLAY, PAUSE             |
| next / previous track             | next/previous | SKIP_FWD / SKIP_REV                        |
| turn off the living room          | room_off      | ROOM_OFF                                   |

Where it reads the names:

- Rooms, lights and custom buttons: the project's devices and their rooms.
- Scenes: the Advanced Lighting agent. Scenarios: custom (Experience) buttons
  and the Macros agent.
- Sources: each room's Listen and Watch lists.

## Actions

- **Refresh Names**: read the names again and print what was found. They are
  also read again on each request older than 30 seconds.
- **Print Context**: print the instructions and names the shortcut gets.
- **Restart Server**
- **Update Drivers**: install the latest release from GitHub now, even when the
  driver is already on it.

## Programming

- **Command Received**: a command was carried out.
- **Command Not Understood**: a command named nothing known or no action.

## HTTP Endpoints

- `GET /context`: text for the Use Model action.
- `POST /execute`: the dictionary as JSON:
  `{"room":"Living Room","action":"volume_set","target":"","value":"30","heard":"living room volume 30"}`.
  Answers with the sentence to speak. `GET /execute?action=...&room=...` works
  too, for testing from a browser.
- `GET /names`: everything the driver knows, as JSON.

## Updates

The driver updates itself from the GitHub releases of
[krishy2/control4-siri-shortcuts](https://github.com/krishy2/control4-siri-shortcuts/releases)
when Automatic Updates is On. The log says when an update was installed and
whether the new version is running.

# <span style="color:#660066">Support</span>

Control Pro - [control-pro.co.uk](https://control-pro.co.uk)

If you have any questions or issues integrating this driver with Control4, you
can file an issue on GitHub:

https://github.com/krishy2/control4-siri-shortcuts/issues/new

If the driver is useful to you, you can buy me a coffee:

<a href="https://buymeacoffee.com/szorfoktato" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>

<!-- #embed-changelog -->
