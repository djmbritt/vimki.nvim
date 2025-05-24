# vimki.nvim

A Neovim plugin that lets you practice your Anki flashcards without leaving your editor.

## Features

- Review due cards from any Anki deck directly in Neovim
- **Practice mode** - Type your answer before revealing the correct one
- Show question/answer format with keyboard controls
- Rate cards with Anki's standard 4-button system (Again/Hard/Good/Easy)
- Track session statistics
- Clean, distraction-free interface
- **Image support for Kitty, WezTerm, and iTerm2 terminals**

## Requirements

- Neovim 0.7+
- [Anki](https://apps.ankiweb.net/) with [AnkiConnect](https://github.com/FooSoft/anki-connect) addon installed
- `curl` command available in your system
- One of these terminals for image support (optional):
  - [Kitty](https://sw.kovidgoyal.net/kitty/)
  - [WezTerm](https://wezfurlong.org/wezterm/)
  - [iTerm2](https://iterm2.com/) (macOS)
- `identify` command from ImageMagick (optional, for image sizing)

## Installation

### Using lazy.nvim

```lua
{
  "your-username/anki-practice.nvim",
  config = function()
    require("anki-practice").setup({
      -- Optional: customize AnkiConnect URL if using non-default port
      anki_connect_url = "http://localhost:8765"
    })
  end,
  cmd = "AnkiPractice", -- Lazy load on command
}
```

### Using packer.nvim

```lua
use {
  'your-username/anki-practice.nvim',
  config = function()
    require('anki-practice').setup()
  end
}
```

### Manual Installation

1. Clone this repository to your Neovim runtime path:

```bash
git clone https://github.com/your-username/anki-practice.nvim \
  ~/.config/nvim/pack/plugins/start/anki-practice.nvim
```

2. Add to your init.lua:

```lua
require('anki-practice').setup()
```

## Setup

1. Install [AnkiConnect](https://github.com/FooSoft/anki-connect) in Anki:
   - Tools → Add-ons → Get Add-ons
   - Enter code: `2055492159`
   - Restart Anki

2. Make sure Anki is running when you want to practice cards

3. Configure the plugin (optional):

```lua
require('anki-practice').setup({
  anki_connect_url = "http://localhost:8765", -- default AnkiConnect URL
  anki_media_dir = "~/Documents/Anki/User 1/collection.media", -- optional: specify Anki media directory
  practice_mode = true -- enable practice mode by default (optional)
})
```

## Usage

Start a practice session:

```vim
:AnkiPractice
```

Or in Lua:

```lua
require('anki-practice').start()
```

### Practice Mode

The plugin includes a practice mode (enabled by default) that encourages active recall:

1. When you see a question, press `a` to open an answer input window
2. Type your answer (multi-line supported)
3. Press `Esc` to save your answer or `Ctrl-C` to cancel
4. Press `Space` to reveal the correct answer
5. Compare your answer with the correct one
6. Rate the card based on how well you did

You can toggle practice mode on/off with the `p` key during a session.

### Keybindings

During a practice session:

**Practice Mode** (default):

- `a` - Type your answer in a popup window
- `Space` - Show the correct answer
- `p` - Toggle between practice and review mode

**Answer Rating**:

- `1` - Rate card as "Again" (didn't remember)
- `2` - Rate card as "Hard"
- `3` - Rate card as "Good"
- `4` - Rate card as "Easy"

**Navigation**:

- `s` - Skip card (won't affect Anki scheduling)
- `r` - Restart session with new deck selection
- `q` - Quit practice session

**In Answer Input Window**:

- `Esc` - Save your answer and close
- `Ctrl-C` - Cancel without saving

## Plugin Structure

```
anki-practice.nvim/
├── lua/
│   ├── anki-practice.lua    # Main plugin logic
│   └── init.lua              # Entry point
├── plugin/
│   └── anki-practice.vim     # Vim command registration (optional)
└── README.md
```

## API

The plugin exposes these functions:

```lua
-- Start a practice session
require('anki-practice').start()

-- Close the practice window
require('anki-practice').close()

-- Show the answer for current card
require('anki-practice').show_answer()

-- Rate the current card (ease: 1-4)
require('anki-practice').rate_card(ease)

-- Skip current card
require('anki-practice').skip_card()

-- Restart session
require('anki-practice').restart_session()

-- Open answer input (in practice mode)
require('anki-practice').open_answer_input()

-- Toggle practice mode
require('anki-practice').toggle_practice_mode()
```

## Troubleshooting

### "Failed to connect to AnkiConnect"

- Make sure Anki is running
- Check that AnkiConnect addon is installed
- Verify AnkiConnect is running on the correct port (default: 8765)

### No cards showing up

- Make sure you have due cards in the selected deck
- Check Anki's scheduler settings
- Try reviewing cards in Anki first to ensure they're properly scheduled

### Cards not displaying correctly

The plugin now supports images via the Kitty image protocol! For text-only terminals, HTML tags are stripped and only text content is shown.

### Image Support

Images are displayed when using supported terminals (Kitty, WezTerm, or iTerm2). The plugin will:

- Automatically detect your terminal type
- Find your Anki media directory (or use the one specified in setup)
- Display images inline with the card content using the appropriate protocol
- Properly scale images to fit the window

Supported terminals:

- **Kitty** - Uses Kitty's graphics protocol
- **WezTerm** - Uses iTerm2 inline images protocol
- **iTerm2** - Uses iTerm2 inline images protocol

If images aren't showing:

- Ensure you're using one of the supported terminals
- Check that the Anki media directory is correctly detected
- Verify that ImageMagick's `identify` command is installed for proper sizing

## Contributing

Pull requests are welcome! Some ideas for improvements:

- [x] Image support (Kitty, WezTerm, iTerm2)
- [ ] Support for cloze deletions
- [ ] Better HTML rendering
- [ ] Audio support
- [ ] Statistics tracking across sessions
- [ ] Custom keybinding configuration
- [ ] Support for filtered decks
- [ ] Undo last rating
- [ ] Support for more image-capable terminals (Konsole, Alacritty with sixel)
- [ ] LaTeX/MathJax rendering

## License

MIT

