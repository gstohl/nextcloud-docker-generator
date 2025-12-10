import { Title } from "@solidjs/meta";
import { createSignal, createMemo, Index, Show } from "solid-js";
import { createStore } from "solid-js/store";
import { generateScript, type Config, type NextcloudInstance } from "~/lib/generateScript";

export default function Home() {
  const [projectDir, setProjectDir] = createSignal("nextcloud-caddy");
  const [acmeEmail, setAcmeEmail] = createSignal("");
  const [instances, setInstances] = createStore<NextcloudInstance[]>([
    { domain: "", adminUser: "admin" },
  ]);
  const [generatedScript, setGeneratedScript] = createSignal("");
  const [copied, setCopied] = createSignal(false);

  function addInstance() {
    setInstances([...instances, { domain: "", adminUser: "admin" }]);
  }

  function removeInstance(idx: number) {
    if (instances.length > 1) {
      setInstances((prev) => prev.filter((_, i) => i !== idx));
    }
  }

  const isValid = createMemo(() => {
    const dir = projectDir();
    const email = acmeEmail();
    return (
      dir.trim() !== "" &&
      email.trim() !== "" &&
      instances.length > 0 &&
      instances.every((inst) => inst.domain.trim() !== "" && inst.adminUser.trim() !== "")
    );
  });

  function generate() {
    if (!isValid()) return;
    const config: Config = {
      projectDir: projectDir(),
      acmeEmail: acmeEmail(),
      instances: [...instances],
    };
    setGeneratedScript(generateScript(config));
  }

  async function copyToClipboard() {
    await navigator.clipboard.writeText(generatedScript());
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }

  return (
    <main class="container">
      <Title>Nextcloud Docker Generator</Title>

      <header class="header">
        <h1>Nextcloud Docker Generator</h1>
        <p class="subtitle">
          Generate a multi-tenant Nextcloud deployment script with Caddy for automatic HTTPS
        </p>
      </header>

      <section class="form-section">
        <h2>Configuration</h2>

        <div class="form-group">
          <label>Project Directory</label>
          <input
            type="text"
            value={projectDir()}
            onInput={(e) => setProjectDir(e.currentTarget.value)}
            placeholder="nextcloud-caddy"
          />
          <span class="hint">Directory name where files will be created</span>
        </div>

        <div class="form-group">
          <label>Let's Encrypt Email</label>
          <input
            type="email"
            value={acmeEmail()}
            onInput={(e) => setAcmeEmail(e.currentTarget.value)}
            placeholder="admin@example.com"
          />
          <span class="hint">Email for SSL certificate notifications</span>
        </div>

        <div class="instances-section">
          <div class="instances-header">
            <h3>Nextcloud Instances</h3>
            <button class="btn btn-secondary" onClick={addInstance}>
              + Add Instance
            </button>
          </div>

          <Index each={instances}>
            {(instance, idx) => (
              <div class="instance-card">
                <div class="instance-header">
                  <span class="instance-number">Instance {idx + 1}</span>
                  <Show when={instances.length > 1}>
                    <button
                      class="btn btn-danger btn-sm"
                      onClick={() => removeInstance(idx)}
                    >
                      Remove
                    </button>
                  </Show>
                </div>

                <div class="instance-fields">
                  <div class="form-group">
                    <label>Domain</label>
                    <input
                      type="text"
                      value={instance().domain}
                      onInput={(e) => setInstances(idx, "domain", e.currentTarget.value)}
                      placeholder="cloud.example.com"
                    />
                  </div>

                  <div class="form-group">
                    <label>Admin Username</label>
                    <input
                      type="text"
                      value={instance().adminUser}
                      onInput={(e) => setInstances(idx, "adminUser", e.currentTarget.value)}
                      placeholder="admin"
                    />
                  </div>
                </div>
              </div>
            )}
          </Index>
        </div>

        <button
          class="btn btn-primary btn-generate"
          disabled={!isValid()}
          onClick={generate}
        >
          Generate Script
        </button>
      </section>

      <Show when={generatedScript()}>
        <section class="output-section">
          <div class="output-header">
            <h2>Generated Script</h2>
            <button class="btn btn-copy" onClick={copyToClipboard}>
              {copied() ? "Copied!" : "Copy to Clipboard"}
            </button>
          </div>

          <div class="code-container">
            <pre><code>{generatedScript()}</code></pre>
          </div>

          <div class="instructions">
            <h3>How to use</h3>
            <ol>
              <li>Copy the script above</li>
              <li>Save it to a file on your server: <code>nano deploy.sh</code></li>
              <li>Make it executable: <code>chmod +x deploy.sh</code></li>
              <li>Run it: <code>./deploy.sh</code></li>
            </ol>
          </div>
        </section>
      </Show>
    </main>
  );
}
