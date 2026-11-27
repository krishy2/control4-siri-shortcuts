<img alt="Control Pro" src="../images/header.png" width="320"/>

<a href="https://buymeacoffee.com/szorfoktato" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>

# Talk to Your Home with Siri

A guide for everyone in the household. By **Control Pro** -
[control-pro.co.uk](https://control-pro.co.uk) -
[c4@control-pro.co.uk](mailto:c4@control-pro.co.uk)

______________________________________________________________________

## What It Does

You say **"Hey Siri, Home"**, Siri listens, and you tell it what you want in
your own words:

- "Turn on the dining light", "Dining light to 40 percent", "Lights off in the
  kitchen"
- "Evening scene", "Run Arrived"
- "Play Sonos in the living room", "Living room volume 30", "A bit quieter",
  "Pause", "Next track", "Turn off the living room"
- "Set the bedroom to 22", "Turn on cooling at 26", "Make it a bit warmer", "How
  warm is it in the bedroom?"

Your home does it and Siri tells you what happened ("Dining on.", "Bedroom cool,
set to 26 degrees."). If something is not clear, Siri asks back ("Which room?").

There is nothing to learn: you do not have to remember exact phrases. Apple's
own AI on your iPhone understands the sentence and picks the right light, scene,
room or music source from your home. When a light is renamed or a room is added,
the shortcut knows it the next time you use it.

You can talk in any language your iPhone's dictation understands. Siri answers
in English, or in your language with the optional
[funny answers](#optional-funny-answers).

## What You Need

- **An iPhone or iPad with Apple Intelligence**, on iOS 26 or later (for example
  iPhone 15 Pro or newer), with Apple Intelligence turned on in Settings.
- **Your home Wi-Fi.** The shortcut talks to your Control4 system directly, so
  it works at home (or over your home VPN).
- **The Siri Shortcuts driver in your Control4 system.** Your installer sets
  this up and gives you either a ready-made shortcut (easiest) or two addresses
  that look like this:
  - `http://192.168.1.10:8765/context`
  - `http://192.168.1.10:8765/execute`

## Getting the Shortcut

### The Easy Way: a Shared Shortcut

If someone in the household already has the shortcut, or your installer sent you
a link:

1. Open the link on your iPhone (from Messages, Mail or AirDrop).
1. Tap **Add Shortcut**.
1. The first time you use it, iOS asks whether the shortcut may connect to your
   home system. Tap **Always Allow**.

That's all. Skip to [Using It](#using-it).

To share your shortcut with someone else: in the **Shortcuts** app, long-press
the shortcut, tap **Share**, and send it by Messages or AirDrop, or choose
**Copy iCloud Link**.

### Building It Yourself

It takes about ten minutes, once. You need the two addresses from your
installer.

Open the **Shortcuts** app and tap **+** at the top. Tap the name at the top and
call it **Home** (or another short word Siri hears well: it is what you will say
to Siri).

Now add six actions, in this order. To add an action, tap the search field at
the bottom, type its name, and tap it.

**1. Get Contents of URL**

- Tap the blue _URL_ and type the first address (the one ending in `/context`).

**2. Dictate Text**

- Tap the small arrow **›** next to it.
- **Stop Listening**: choose **After Pause**.
- **Language**: the language you will speak.

**3. Text**

- Tap in the text box, then **Select Variable** in the bar above the keyboard,
  and tap **Contents of URL**.
- Press **return** for a new line and type `Request: ` (with a space after the
  colon).
- Tap **Select Variable** again and tap **Dictated Text**.

It looks like this:

```
[Contents of URL]
Request: [Dictated Text]
```

**4. Use Model**

- Tap the model name and choose **Cloud**.
- The text box should show **Text**. If it is empty, tap it and choose **Text**
  from the variables.
- Tap the arrow **›** and set **Output** to **Dictionary**. Leave the other
  switches off.

**5. Get Contents of URL** (a second one)

- Tap the blue _URL_ and type the second address (the one ending in `/execute`).
- Tap the arrow **›**:
  - **Method**: **POST**
  - **Request Body**: **File**
  - **File**: tap it and choose **Response** (the answer of Use Model).

**6. Speak Text**

- It should say **Speak Contents of URL**. If not, tap the blue word and choose
  the **Contents of URL** of step 5.
- Tap the arrow **›** to choose the voice you like.

Tap **Done**. Your shortcut is ready.

## Using It

1. Say **"Hey Siri, Home"** (or the name you chose).
1. Wait for Siri to listen, then say what you want: "Turn on the dining light".
1. Siri tells you what was done.

You can also tap the shortcut in the Shortcuts app, or add it to your Home
Screen or Control Center.

Tips:

- Say the room when it matters: "Living room volume 30", "Set the bedroom to
  22".
- Without a room, music and volume commands go to your home's main room (your
  installer sets which).
- Questions work too: "How warm is it in the bedroom?"

## Optional: Funny Answers

Your home answers plainly ("Dining on."). If you would like a witty voice
instead, in your own language, let Apple's AI rewrite the answer before Siri
speaks it. Replace step 6 (**Speak Text**) with three actions:

**6. Text**, with this content. Put **Dictated Text** and the **Contents of
URL** of step 5 where the brackets are (with **Select Variable**):

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

**7. Use Model**: choose **On-Device**, the text box shows **Text** (step 6),
and set **Output** to **Text**.

**8. Speak Text**: speak the **Response** of step 7. Set its language and voice
to your language.

Change the first line to give your home another character, for example "You are
a sarcastic English butler." It takes a second longer per request.

## If Something Goes Wrong

| What happens                         | What to do                                                                                          |
| ------------------------------------ | --------------------------------------------------------------------------------------------------- |
| Siri says it cannot connect          | Make sure you are on the home Wi-Fi. Check the two addresses (ask your installer).                  |
| "Sorry, the command did not arrive." | Check step 5: Method **POST**, Request Body **File**, File **Response**.                            |
| "Sorry, I can't do that."            | The request was not about lights, scenes, music or temperature, or named something not in the home. |
| "Which room?" / "Which one: …?"      | Say the room or the full name: "the ceiling light in the bedroom".                                  |
| It picks the wrong light or room     | Say it more precisely. If it keeps happening, tell your installer: they can add a hint.             |
| Use Model is missing in Shortcuts    | Your iPhone needs Apple Intelligence (iOS 26 or later, iPhone 15 Pro or newer) turned on.           |

## Privacy

- The shortcut talks only to your own Control4 system, on your home network.
  There is no Control Pro server or account.
- To understand you, the **Use Model** step sends your sentence and the names of
  your rooms and devices to Apple's AI (**Cloud** uses Apple's Private Cloud
  Compute). Nothing else from your home is sent.
- There is no password: any device on your home network can send commands to it.
  Keep your Wi-Fi password to the household and guests you trust.

______________________________________________________________________

Questions? Ask your installer, visit
[control-pro.co.uk](https://control-pro.co.uk), or write to
[c4@control-pro.co.uk](mailto:c4@control-pro.co.uk).

If this is useful to you, you can buy me a coffee:

<a href="https://buymeacoffee.com/szorfoktato" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>
