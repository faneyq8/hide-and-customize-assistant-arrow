# HCAA v1.5.0

## Hide & Customize Assistant Arrow

HCAA is a lightweight World of Warcraft addon that lets you hide or customize Blizzard's Single-Button Assistant Arrow.

## Features

- Hide the Assistant Arrow completely.
- Keep Blizzard's original arrow on the default Blizzard UI.
- Choose from 20 built-in custom frame styles.
- Custom arrow and glow colors.
- Opacity, scale, rotation, and X/Y position controls.
- Live in-game preview.
- Combat and zone visibility rules.
- Account-wide, character, or specialization setting scope.
- Draggable minimap button.
- Lightweight, event-driven detection.

## Supported Interfaces

- Blizzard Default UI
- ElvUI
- EllesmereUI

HCAA automatically detects the active interface and applies the appropriate behavior.

## Minimap Controls

- **Left-click:** Open settings.
- **Right-click:** Enable or disable HCAA.
- **Middle-click:** Hide the arrow.
- **Mouse wheel:** Adjust opacity.
- **Drag:** Move the minimap button.

## Slash Commands

```text
/hcaa
/hcaa on
/hcaa off
/hcaa toggle
/hcaa opacity 0-100
/hcaa mode hidden|original|custom
/hcaa shape NAME
/hcaa reset
```

## Author

**FaneyQ8**

## Custom frame image
Open **General > Shapes > Custom**. Put a square `.tga`, `.blp`, or `.dds` image in `HCAA/Custom`, then enter its filename without the extension. A 256x256 transparent image is recommended. Use `/reload` after adding or replacing the file while World of Warcraft is running.
