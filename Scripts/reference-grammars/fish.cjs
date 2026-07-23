/*
 * HighlightKit's first-party Fish reference grammar.
 *
 * Authored from the Fish language documentation/source at
 * 20569c43d851ad65c77798434ccccb5610dbe3a1. This JavaScript grammar is
 * the differential oracle for Sources/HighlightKit/Languages/Fish.swift.
 */
module.exports = function fish(hljs) {
  const VARIABLE = {
    scope: 'variable',
    variants: [
      { match: /\$\{[A-Za-z_][A-Za-z0-9_]*\}/ },
      { match: /\$[A-Za-z_][A-Za-z0-9_]*(?:\[[^\]\n]+\])?/ }
    ],
    relevance: 0
  };
  const ESCAPE = {
    scope: 'char.escape',
    match: /\\(?:[abefnrtv\\"'$]|x[0-9A-Fa-f]{1,2}|u[0-9A-Fa-f]{1,4}|U[0-9A-Fa-f]{1,8})/,
    relevance: 0
  };
  const SUBST = { scope: 'subst', begin: /\(/, end: /\)/, relevance: 0 };
  const SINGLE = { scope: 'string', begin: /'/, end: /'/ };
  const DOUBLE = {
    scope: 'string', begin: /"/, end: /"/,
    contains: [ESCAPE, VARIABLE, SUBST]
  };
  SUBST.contains = [
    hljs.HASH_COMMENT_MODE,
    SINGLE,
    DOUBLE,
    VARIABLE,
    'self'
  ];
  return {
    name: 'Fish',
    aliases: ['fish'],
    disableAutodetect: true,
    keywords: {
      $pattern: /[A-Za-z_][A-Za-z0-9_-]*/,
      keyword: [
        'and', 'begin', 'break', 'case', 'command', 'continue', 'else', 'end',
        'exec', 'for', 'function', 'if', 'in', 'not', 'or', 'return', 'switch',
        'time', 'while'
      ],
      literal: ['true', 'false']
    },
    contains: [
      hljs.SHEBANG({ binary: 'fish', relevance: 10 }),
      hljs.HASH_COMMENT_MODE,
      SINGLE,
      DOUBLE,
      VARIABLE,
      SUBST,
      { scope: 'meta', match: /--?[A-Za-z][A-Za-z0-9_-]*/, relevance: 0 },
      { scope: 'operator', match: /(?:\|&?|&&|\|\||[0-9]*>{1,2}\??|[0-9]*<)/, relevance: 0 },
      hljs.C_NUMBER_MODE
    ]
  };
};
