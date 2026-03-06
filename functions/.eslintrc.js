module.exports = {
  env: {
    es6: true,
    node: true,
  },
  parserOptions: {
    "ecmaVersion": 2018,
  },
  extends: [
    "eslint:recommended",
    "google",
  ],
  rules: {
    "no-restricted-globals": ["error", "name", "length"],
    "prefer-arrow-callback": "error",
    "quotes": ["error", "double", {"allowTemplateLiterals": true}],
    "object-curly-spacing": "off",
    "max-len": "off",
    "camelcase": "off",
    "require-jsdoc": "off",
    "valid-jsdoc": "off",
    "no-invalid-this": "off",
    "brace-style": "off",
    "block-spacing": "off",
    "no-empty": "off",
    "comma-dangle": "off",
    "prefer-const": "off",
  },
  overrides: [
    {
      files: ["**/*.spec.*"],
      env: {
        mocha: true,
      },
      rules: {},
    },
  ],
  globals: {},
};
