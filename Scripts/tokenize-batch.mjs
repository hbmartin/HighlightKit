// Batch reference tokenizer. Reads JSONL {lang, code} from stdin,
// emits JSONL {tokens, relevance, error?} — one line per input.
import path from 'node:path';
import { existsSync } from 'node:fs';
import { createRequire } from 'node:module';
import readline from 'readline';

const referenceRoot = process.env.HIGHLIGHTJS_DIR;
if (!referenceRoot) {
  throw new Error('set HIGHLIGHTJS_DIR to a highlight.js source checkout');
}
const buildRoot = path.join(referenceRoot, 'build', 'lib');
const corePath = path.join(buildRoot, 'core.js');
if (!existsSync(corePath)) {
  throw new Error(
    'missing highlight.js Node build; run `npm ci && npm run build` in HIGHLIGHTJS_DIR'
  );
}
const require = createRequire(import.meta.url);
const HLJS = require(corePath).newInstance();

const SUPPORTED = `plaintext ada apache applescript armasm bash basic c clojure cmake coffeescript cpp csharp css dart delphi diff dockerfile dos elm elixir erlang fortran fsharp go graphql groovy haskell http ini java javascript json kotlin leaf less lisp llvm lua makefile markdown matlab nginx nim nix objectivec ocaml perl php powershell prolog properties protobuf python r ruby rust scala scheme scss shell sql stylus swift typescript vim xml yaml`.split(' ');

class Emitter {
  constructor(){ this.stack=[]; this.offset=0; this.tokens=[]; }
  addText(t){ if(t) this._a(t.length); }
  _a(n){ if(n<=0) return; if(this.stack.length){ const sc=this.stack.slice(); const l=this.tokens[this.tokens.length-1];
    if(l && l.start+l.length===this.offset && JSON.stringify(l.scopes)===JSON.stringify(sc)) l.length+=n;
    else this.tokens.push({start:this.offset,length:n,scopes:sc}); } this.offset+=n; }
  startScope(s){ this.stack.push(s); } endScope(){ this.stack.pop(); }
  openNode(s){ this.stack.push(s); } closeNode(){ this.stack.pop(); }
  __addSublanguage(sub){ const b=this.offset; let p=0;
    for(const t of sub.tokens){ if(t.start>p) this._a(t.start-p); const sc=this.stack.concat(t.scopes);
      if(t.length>0){ const l=this.tokens[this.tokens.length-1];
        if(l && l.start+l.length===b+t.start && JSON.stringify(l.scopes)===JSON.stringify(sc)) l.length+=t.length;
        else this.tokens.push({start:b+t.start,length:t.length,scopes:sc}); }
      this.offset=b+t.start+t.length; p=t.start+t.length; }
    if(sub.offset>p) this._a(sub.offset-p); }
  finalize(){} toHTML(){ return ''; }
}

// highlight.js's zero-width illegal-at-EOF recovery appends a synthetic
// newline to its output buffer even when the source has no newline. That is
// meaningful to its HTML emitter, but cannot be represented as an NSRange
// into the original string. Keep the oracle source-bounded and report every
// clipped unit so campaigns can audit rather than silently hide the case.
function sourceBoundTokens(tokens, sourceLength) {
  const bounded = [];
  let eofUnitsClipped = 0;
  for (const [index, token] of tokens.entries()) {
    const { start, length } = token;
    if (start < 0 || length < 0 || start > sourceLength) {
      throw new Error("reference emitted invalid token " + JSON.stringify(token));
    }
    const end = start + length;
    if (end <= sourceLength) {
      bounded.push(token);
      continue;
    }
    if (index !== tokens.length - 1 || end !== sourceLength + 1) {
      throw new Error(
        "reference token exceeds source by more than the known EOF newline: "
          + JSON.stringify(token)
      );
    }
    eofUnitsClipped += 1;
    const clippedLength = sourceLength - start;
    if (clippedLength > 0) {
      bounded.push({ ...token, length: clippedLength });
    }
  }
  return { tokens: bounded, eofUnitsClipped };
}

for (const n of SUPPORTED) {
  const language = require(path.join(buildRoot, 'languages', `${n}.js`));
  HLJS.registerLanguage(n, language);
}
const terraformRoot = process.env.HIGHLIGHTJS_TERRAFORM_DIR;
if (terraformRoot) {
  const terraform = require(path.join(terraformRoot, 'terraform.js'));
  HLJS.registerLanguage('terraform', terraform.definer);
}
const zigRoot = process.env.HIGHLIGHTJS_ZIG_DIR;
if (zigRoot) {
  const zig = require(path.join(zigRoot, 'src', 'index.js'));
  HLJS.registerLanguage('zig', zig.zigLanguageSupport);
}
HLJS.configure({ __emitter: Emitter });

const rl = readline.createInterface({ input: process.stdin });
for await (const line of rl) {
  if(!line) { console.log('{}'); continue; }
  let out;
  try { const {lang, code} = JSON.parse(line);
    const r = HLJS.highlight(code, { language: lang, ignoreIllegals: true });
    const bounded = sourceBoundTokens(r._emitter.tokens, code.length);
    out = {
      tokens: bounded.tokens,
      relevance: r.relevance,
      referenceEOFUnitsClipped: bounded.eofUnitsClipped
    };
  } catch(e){ out = { error: String(e).slice(0,200) }; }
  process.stdout.write(JSON.stringify(out) + '\n');
}
