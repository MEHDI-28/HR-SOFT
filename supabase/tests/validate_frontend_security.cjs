const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const root = path.resolve(__dirname, "..", "..");
const htmlFiles = ["index.html", "org-structure-manager.html"];
const clientFiles = [
  "auth.html",
  "index.html",
  "org-structure-manager.html",
  "org-structure-readonly.html",
  "supabase-config.example.js",
];

function extractFunction(source, name) {
  const pattern = new RegExp(
    "function " + name + "\\(s\\)\\s*\\{[\\s\\S]*?\\n\\s*\\}"
  );
  const match = source.match(pattern);
  assert.ok(match, name + " function not found");
  return match[0];
}

function loadFunction(source, name) {
  const context = {};
  vm.runInNewContext(
    extractFunction(source, name) + "; this.fn = " + name + ";",
    context
  );
  return context.fn;
}

const decodeHtmlAttributeOnce = (value) => {
  const entities = {
    amp: "&",
    lt: "<",
    gt: ">",
    quot: '"',
    "#39": "'",
  };
  return value.replace(/&(amp|lt|gt|quot|#39);/g, (_, key) => entities[key]);
};

const payloads = [
  "normal-position-id",
  'double"quote',
  "single'quote",
  "backslash\\\\'); flag = true; //",
  "</button><img src=x onerror=flag=true>",
  '&quot; onmouseover=&quot;flag=true',
  "line\\nbreak\\u2028\\u2029",
  "'); flag = true; //",
];

for (const file of htmlFiles) {
  const source = fs.readFileSync(path.join(root, file), "utf8");
  const escapeAttr = loadFunction(source, "escapeAttr");
  const escapeHtml = loadFunction(source, "escapeHtml");

  for (const payload of payloads) {
    const encoded = escapeAttr(JSON.stringify(payload));
    const decoded = decodeHtmlAttributeOnce(encoded);
    let captured;
    const sandbox = {
      flag: false,
      capture: (value) => {
        captured = value;
      },
    };

    vm.runInNewContext("capture(" + decoded + ")", sandbox);
    assert.equal(captured, payload, file + ": inline handler argument changed");
    assert.equal(sandbox.flag, false, file + ": inline handler injection executed");
  }

  const htmlPayload = '<img src=x onerror="alert(1)">';
  const escapedText = escapeHtml(htmlPayload);
  assert.ok(!escapedText.includes("<img"), file + ": HTML text was not escaped");
  assert.ok(escapedText.includes("&lt;img"), file + ": expected HTML escaping");

  assert.match(
    source,
    /editPosition\(\$\{escapeAttr\(JSON\.stringify\(p\.id\)\)\}\)/,
    file + ": editPosition id must be JSON-stringified and HTML-escaped"
  );
  assert.match(
    source,
    /deletePosition\(\$\{escapeAttr\(JSON\.stringify\(p\.id\)\)\}\)/,
    file + ": deletePosition id must be JSON-stringified and HTML-escaped"
  );
  assert.doesNotMatch(
    source,
    /(?:editPosition|deletePosition)\('\$\{escapeAttr\(p\.id\)\}'\)/,
    file + ": unsafe inline handler pattern remains"
  );

  if (file === "index.html") {
    assert.match(
      source,
      /<span class="text-slate-400">\$\{escapeHtml\(dateStr\)\}<\/span>/,
      "index.html: history date must be HTML-escaped"
    );
  }

  console.log("PASS: " + file + " dynamic HTML/inline-handler escaping");
}

const privilegedSecretPattern = /sb_secret_[A-Za-z0-9_-]{16,}|(?:service_role|SUPABASE_SERVICE_ROLE_KEY)\s*[:=]\s*["'][^"']{8,}["']/i;
assert.match(
  "SUPABASE_SERVICE_ROLE_KEY = 'abcdefghijklmnop'",
  privilegedSecretPattern,
  "secret detector must catch service-role key assignments with spaces"
);
assert.match(
  "service_role:'abcdefghijklmnop'",
  privilegedSecretPattern,
  "secret detector must catch compact service_role assignments"
);
assert.doesNotMatch(
  "SUPABASE_ANON_KEY = 'abcdefghijklmnop'",
  privilegedSecretPattern,
  "secret detector must not flag a publishable anon-key variable"
);

for (const file of clientFiles) {
  const source = fs.readFileSync(path.join(root, file), "utf8");
  assert.doesNotMatch(
    source,
    /sb_secret_[A-Za-z0-9_-]{16,}|(?:service_role|SUPABASE_SERVICE_ROLE_KEY)\s*[:=]\s*[\"'][^\"']{8,}[\"']/i,
    file + ": privileged Supabase secret reference found in client source"
  );
}
const readonlyPage = fs.readFileSync(
  path.join(root, "org-structure-readonly.html"),
  "utf8"
);
assert.match(
  readonlyPage,
  /client\.rpc\(['"]hr_admin_get_context_v1['"]\)/,
  "read-only page must use the authenticated admin context RPC"
);
assert.match(
  readonlyPage,
  /client\.rpc\(['"]hr_org_get_admin_snapshot_v1['"]\s*,/,
  "read-only page must use the organization snapshot RPC"
);
assert.doesNotMatch(
  readonlyPage,
  /localStorage|sessionStorage|\.from\s*\(|\.insert\s*\(|\.update\s*\(|\.delete\s*\(/,
  "read-only page must not use browser storage, direct table access, or write methods"
);
assert.doesNotMatch(
  readonlyPage,
  /innerHTML/,
  "read-only page must not inject API data through innerHTML"
);
assert.match(
  readonlyPage,
  /textContent/,
  "read-only page must render API data as text"
);
console.log("PASS: read-only organization page uses only the scoped RPCs and safe text rendering");
console.log("PASS: no service-role/secret-key reference in browser-facing files");
console.log("FRONTEND SECURITY STATIC TESTS: PASS");
