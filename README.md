## Neovim-AI

A Neovim simple plugin to integrate with AI.

#### Current Features

- AI Chat in floating window
- AI Code explanation
- Simple history management

#### Installation

- `vim-plug`

```
call plug#begin()

Plug 'kiminandayo19/nvim-ai'

call plug#end()

lua << EOF
require('floating').setup({
  config = {
    api_url = os.getenv("AI_MODEL_URL"),
    api_key = os.getenv("YOUR_AI_API_KEY"),
    model = "YOUR_AI_MODEL"
  },
  system_role = "You are a helpful AI Asistant",
  max_conversation_history_len = 10,
})
EOF
```
