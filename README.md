## Neovim-AI

A Neovim simple plugin to integrate with AI.

#### Features

- **AI Chat**: Engage in conversations with AI in a floating window.
- **Code Explanation**: Get explanations for your code snippets.
- **History Management**: Maintain a simple history of your interactions.

#### Installation

<details>
<summary>Installation with vim-plug</summary>

```vim
call plug#begin()

Plug 'kiminandayo19/nvim-ai'

call plug#end()

lua << EOF
require('nvim_ai').setup({
  config = {
    api_url = os.getenv("AI_MODEL_URL"),
    api_key = os.getenv("YOUR_AI_API_KEY"),
    model = "YOUR_AI_MODEL"
  },
  system_role = "You are a helpful AI Assistant",
  max_conversation_history_len = 10,
})
EOF
```

</details>

#### Keybindings

- Open AI floating window chat: `<leader>of`
- Clear chat history: `<leader>cf`
- Explain code: `<leader>ssf` (works in normal and visual modes)
