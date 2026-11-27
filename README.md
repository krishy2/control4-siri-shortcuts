<!-- Copyright 2026 Control Pro (control-pro.co.uk). All rights reserved. -->

<img alt="Control Pro" src="./images/header.png" width="400"/>

______________________________________________________________________

# <span style="color:#660066">Overview</span>

Siri Shortcuts driver by **Control Pro** -
[control-pro.co.uk](https://control-pro.co.uk)

> DISCLAIMER: This software is neither affiliated with nor endorsed by either
> Control4 or Apple.

The Siri Shortcuts driver lets you control the home by voice from an iPhone or
iPad with one Apple Shortcut: lights, Advanced Lighting scenes, scenarios
(custom buttons and macros), room media (sources, volume, mute, play, pause,
tracks, room off) and thermostats (temperature, warmer, cooler, mode, and "how
warm is it?"). It needs no extra hardware, no cloud service and no Control4
subscription.

Apple's own AI does the understanding. The shortcut asks the driver for the
project's names, lets the Shortcuts **Use Model** action turn what you said into
a command, and sends that command back to the driver, which carries it out and
answers with a sentence for Siri to speak.

**For the household:** the
[User Guide](https://github.com/krishy2/control4-siri-shortcuts/blob/main/documentation/user-guide.md)
explains to end users what the driver does, what they need, and how to build or
add the shortcut. Send them that link.

The shortcut contains nothing about your project: rename a light in Composer and
the next request already uses the new name.

# <span style="color:#660066">Index</span>

<div style="font-size: small">

- [System Requirements](#system-requirements)
- [Installer Setup](#installer-setup)
  - [Driver Installation](#driver-installation)
- [Creating the Shortcut](#creating-the-shortcut)
  - [Before You Start](#before-you-start)
  - [Build It Step by Step](#build-it-step-by-step)
  - [Try It](#try-it)
  - [Alternative: Funny Answers](#alternative-funny-answers)
  - [Share It with Your Household](#share-it-with-your-household)
  - [If Something Goes Wrong](#if-something-goes-wrong)
- [Driver Reference](#driver-reference)
  - [Driver Properties](#driver-properties)
  - [Commands](#commands)
  - [Actions](#actions)
  - [Programming](#programming)
  - [HTTP Endpoints](#http-endpoints)
  - [Updates](#updates)
- [Support](#support)

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
1. Note the **Context URL** and **Execute URL** properties: the shortcut needs
   them.
1. Create the shortcut once (next section) and share it with the household.

# <span style="color:#660066">Creating the Shortcut</span>

The shortcut is made once, on one iPhone, then shared with everyone in the
household. It holds no names from the project: the driver sends them each time,
so the shortcut never needs editing when the project changes.

## Before You Start

- An iPhone or iPad with Apple Intelligence turned on (iOS 26 or later): the
  shortcut uses Apple's **Use Model** action.
- The **Context URL** and **Execute URL** from the driver's properties in
  Composer, e.g. `http://192.168.1.10:8765/context` and
  `http://192.168.1.10:8765/execute`.
- The phone on the home network.

## Build It Step by Step

Open the **Shortcuts** app, tap **+**, and name the shortcut with a short word
Siri hears well, e.g. **Home** (tap the name at the top to rename it). Then add
these six actions in this order (tap **Add Action** or the search field, type
the action's name, tap it):

1. **Get Contents of URL**
   - Tap _URL_ and type the **Context URL**.
   - Leave the method on **GET**.
1. **Dictate Text**
   - Tap **›** and set **Stop Listening** to **After Pause**.
   - **Language**: the language you will speak.
1. **Text**
   - Long-press in the text box, choose **Select Variable**, and pick **Contents
     of URL** (from step 1).
   - Press return to start a new line, type `Request: ` and insert the variable
     **Dictated Text** after it.
1. **Use Model**
   - Tap the model and choose **Cloud**.
   - The text box shows **Text** (from step 3); if not, insert it.
   - Tap **›** and set **Output** to **Dictionary**. Leave Follow Up off.
1. **Get Contents of URL**
   - Tap _URL_ and type the **Execute URL**.
   - Tap **›**: **Method** **POST**, **Request Body** **File**, **File** =
     **Response** (from Use Model).
1. **Speak Text**
   - Speak **Contents of URL** (from step 5, the second one).
   - Tap **›** to choose the voice and its language.

## Try It

Say **"Hey Siri, Home"**. Siri listens; then say the request:

- "Turn on the dining light", "Dining light to 40 percent"
- "Lights off in the kitchen"
- "Evening scene", "Run Arrived"
- "Play Sonos in the living room", "Living room volume 30", "A bit quieter"
- "Pause", "Next track", "Turn off the living room"
- "Set the bedroom to 22", "Make it a bit cooler", "Cool mode", "How warm is it
  in the bedroom?"

Siri answers with what was done ("Dining on.") or asks back ("Which room?"). The
request can be in any language the dictation understands; the names are matched
to the project's names.

## Alternative: Funny Answers

The driver always answers plainly. To have a witty voice instead, the shortcut
can let Apple's AI rewrite the answer before Siri speaks it, in the language of
the request. Replace step 6 (**Speak Text**) with three actions:

6. **Text**, with this content (insert **Dictated Text** and the **Contents of
   URL** of step 5 where shown):

   ```
   You are the witty voice of a smart home.
   Rewrite the home's answer as ONE short, funny spoken sentence
   (at most 20 words), in the same language as the user's request.
   Keep every fact exactly: names, numbers, on or off, the room.
   If the answer is a question or a problem, stay clear about
   what the user should do. No emojis, no quotation marks.

   User's request: [Dictated Text]
   Home's answer: [Contents of URL]
   ```

1. **Use Model**: **On-Device** (fastest; Cloud for better jokes), input the
   Text of step 6, Output **Text**.

1. **Speak Text**: the **Response** of step 7.

Change the first line to give it another character, e.g. "a sarcastic English
butler". It adds a second or so to each request. The driver's **Last Reply**
property still shows the plain answer.

## Share It with Your Household

1. In Shortcuts, long-press the shortcut, tap **Share**, then **Copy iCloud
   Link** (or AirDrop / Messages to the family member).
1. They open the link on their iPhone and tap **Add Shortcut**.
1. The first time it runs, iOS asks to allow the shortcut to connect to the
   controller: tap **Allow** (and **Always Allow**, so it does not ask again).

Everyone gets the same shortcut; nothing needs changing on their phone except,
if they like, the dictation language (step 2) and the voice (last step). Each
phone needs Apple Intelligence and the home network.

## If Something Goes Wrong

- **"Sorry, the command did not arrive."**: check step 5: method POST, Request
  Body File, File = Response.
- **Siri says it cannot connect**: the phone is not on the home network, or the
  URL or port is wrong (compare with the driver's properties).
- **The wrong light or room**: look at **Last Command** in Composer to see what
  the AI understood; add a hint in **Extra Instructions**, or hide names it
  should not use with **Hidden Names**.
- **Test without switching anything**: set **Execute Commands** to No; the
  driver answers "Test mode. ..." and sends nothing.

# <span style="color:#660066">Driver Reference</span>

## Driver Properties

### Update Settings

- **Automatic Updates** \[ Off | **_On_** \]: install new releases from GitHub
  by themselves, checked every 30 minutes.
- **Update Channel** \[ **_Production_** | Prerelease \]: Prerelease also
  installs test releases.

### Driver Settings

- **Driver Status** (read-only): whether the driver listens.
- **Driver Version** (read-only)
- **Log Level**, **Log Mode**: Log Mode Print shows the log in Composer's Lua
  Output; Debug logs every request, Trace also its body.

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

| Say                               | Action             | Control4                                   |
| --------------------------------- | ------------------ | ------------------------------------------ |
| turn on / off the dining light    | light_on/off       | light ON / OFF                             |
| lights off in the kitchen         | light_off          | every light of the room OFF                |
| dining light to 40 percent        | light_level        | SET_BRIGHTNESS_TARGET                      |
| evening scene / evening scene off | scene              | Advanced Lighting ACTIVATE / DEACTIVATE    |
| run Arrived                       | scenario           | custom button SELECT / macro EXECUTE_MACRO |
| play Sonos in the living room     | source             | room SELECT_AUDIO / SELECT_VIDEO_DEVICE    |
| living room volume 30             | volume_set         | SET_VOLUME_LEVEL                           |
| a bit louder / quieter            | volume_up/dn       | SET_VOLUME_LEVEL from the room's volume    |
| mute, unmute, play, pause         | ...                | MUTE_ON, MUTE_OFF, PLAY, PAUSE             |
| next / previous track             | next/previous      | SKIP_FWD / SKIP_REV                        |
| turn off the living room          | room_off           | ROOM_OFF                                   |
| set the bedroom to 22             | thermostat_set     | SET_SETPOINT_HEAT / COOL / SINGLE          |
| warmer / cooler (by 2 degrees)    | thermostat_up/down | the setpoint in use ± 1 (or the number)    |
| cool mode, turn the heating off   | thermostat_mode    | SET_MODE_HVAC (the thermostat's own modes) |
| how warm is it in the bedroom?    | temperature        | reads the temperature and setpoint         |

Where it reads the names:

- Rooms, lights and custom buttons: the project's devices and their rooms.
- Scenes: the Advanced Lighting agent. Scenarios: custom (Experience) buttons
  and the Macros agent.
- Sources: each room's Listen and Watch lists.
- Thermostats: the project's thermostats (thermostatV2 proxy) and the modes each
  offers.

Thermostats:

- Temperatures are in the project's scale (Celsius or Fahrenheit).
- A thermostat is found by its name, by the room ("set the bedroom to 22"), or
  it is the only one. With none named, the Default Room's thermostat is used.
- The setpoint follows the mode: Cool sets the cooling setpoint, Heat the
  heating one. In Auto, a target above the room temperature sets heating, below
  it cooling. Warmer and cooler move the setpoint in use.
- A mode in the same request is switched first: "turn on cooling at 26" sets
  Cool, then the cooling setpoint to 26. Without a mode, an off thermostat stays
  off and the answer says so.

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
  `{"room":"Living Room","action":"volume_set","target":"","value":"30","mode":"","heard":"living room volume 30"}`.
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
