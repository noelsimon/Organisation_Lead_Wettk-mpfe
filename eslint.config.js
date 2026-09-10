import js from "@eslint/js";

// Bewusst schlank gehalten (Issue #1 "Test- und Lint-Grundgerüst"): fängt
// echte Bugs (undefinierte Variablen, kaputte Syntax, unreachable code, …),
// meckert aber nicht über den bestehenden ES5-nahen Stil der Datei
// (var statt let/const, etc.) - das ist bewusst kein Refactoring-Ticket.
export default [
  {
    ignores: ["node_modules/**", "src/regieplan-fragment.html", "index.html"],
  },
  {
    files: [".eslint-tmp/script.part.js"],
    languageOptions: {
      ecmaVersion: 2021,
      sourceType: "script",
      globals: {
        window: "readonly",
        document: "readonly",
        localStorage: "readonly",
        navigator: "readonly",
        console: "readonly",
        setTimeout: "readonly",
        clearTimeout: "readonly",
        fetch: "readonly",
        FormData: "readonly",
        Blob: "readonly",
        URL: "readonly",
        alert: "readonly",
        confirm: "readonly",
        prompt: "readonly",
        history: "readonly",
        location: "readonly",
        CSS: "readonly",
        URLSearchParams: "readonly",
        FileReader: "readonly",
        // eingebunden über <script src> in config.part / head.part
        jspdf: "readonly",
        Chart: "readonly",
      },
    },
    rules: {
      ...js.configs.recommended.rules,
      "no-unused-vars": "warn",
      "no-empty": "warn",
      "no-cond-assign": ["error", "except-parens"],
    },
  },
  {
    files: ["tests/**/*.js", "scripts/**/*.mjs", "vitest.config.js"],
    languageOptions: {
      ecmaVersion: 2021,
      sourceType: "module",
      globals: {
        process: "readonly",
        console: "readonly",
        setTimeout: "readonly",
      },
    },
    rules: js.configs.recommended.rules,
  },
];
