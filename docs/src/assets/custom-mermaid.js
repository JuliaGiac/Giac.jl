async function initMermaid() {
    try {
        // Fetch the single-file UMD version of Mermaid
        const res = await fetch('https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js');
        let text = await res.text();
        
        // Strip out all AMD (require.js) checks. 
        // This prevents bundled libraries (like dayjs and fastdom) from 
        // registering as anonymous AMD modules and crashing Mermaid.
        text = text.replace(/typeof define/g, '"undefined"');
        
        // Inject the patched script into the page
        const script = document.createElement('script');
        script.innerHTML = text;
        document.body.appendChild(script);
        
        // Initialize and run Mermaid
        if (window.mermaid) {
            window.mermaid.initialize({ startOnLoad: false, theme: 'neutral' });
            
            // Documenter outputs <pre><code class="language-mermaid">
            // Replace these with <div class="mermaid"> to avoid the `<pre>` gray box.
            document.querySelectorAll('.language-mermaid').forEach(node => {
                if (node.parentElement && node.parentElement.tagName === 'PRE') {
                    const div = document.createElement('div');
                    div.className = 'mermaid';
                    div.textContent = node.textContent;
                    node.parentElement.replaceWith(div);
                } else {
                    node.className = 'mermaid';
                }
            });
            
            await window.mermaid.run({ querySelector: '.mermaid' });
        }
    } catch (e) {
        console.error('Mermaid render error:', e);
    }
}

if (document.readyState === 'loading') {
    document.addEventListener("DOMContentLoaded", initMermaid);
} else {
    initMermaid();
}
