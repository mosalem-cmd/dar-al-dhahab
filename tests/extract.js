// Extract calc / num / fmt from index.html and run them in an isolated vm sandbox.
// استخراج دوال الحساب من index.html دون تعديل التطبيق.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');

// One-line const declarations: AR, num, fmt
function line(name) {
  const m = html.match(new RegExp(`^const ${name}=.*;$`, 'm'));
  if (!m) throw new Error(`Could not find "const ${name}=" in index.html`);
  return m[0];
}

// function calc(i){...}: take everything up to the matching closing brace
function calcSource() {
  const start = html.indexOf('function calc(i){');
  if (start < 0) throw new Error('Could not find "function calc(i){" in index.html');
  let depth = 0;
  for (let i = html.indexOf('{', start); i < html.length; i++) {
    if (html[i] === '{') depth++;
    else if (html[i] === '}' && --depth === 0) return html.slice(start, i + 1);
  }
  throw new Error('Unbalanced braces in calc()');
}

const code = [line('AR'), line('num'), line('fmt'), calcSource(), 'this.api={calc,num,fmt};'].join('\n');
const ctx = vm.createContext({});
vm.runInContext(code, ctx);

module.exports = ctx.api;
