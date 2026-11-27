.pragma library
// This exists only because I haven't been able to get linkColor to work with MarkdownText
// May not be necessary if that's possible tbh.
function markdownToHtml(text) {
    if (!text) return "";

    const codeBlocks = [];
    const inlineCode = [];
    let blockIndex = 0;
    let inlineIndex = 0;

    let html = text.replace(/```([\s\S]*?)```/g, (match, code) => {
        const trimmedCode = code.replace(/^\n+|\n+$/g, '');
        const escapedCode = trimmedCode.replace(/&/g, '&amp;')
                                       .replace(/</g, '&lt;')
                                       .replace(/>/g, '&gt;');
        codeBlocks.push(`<pre><code>${escapedCode}</code></pre>`);
        return `\x00CODEBLOCK${blockIndex++}\x00`;
    });

    html = html.replace(/`([^`]+)`/g, (match, code) => {
        const escapedCode = code.replace(/&/g, '&amp;')
                               .replace(/</g, '&lt;')
                               .replace(/>/g, '&gt;');
        inlineCode.push(`<code>${escapedCode}</code>`);
        return `\x00INLINECODE${inlineIndex++}\x00`;
    });

    // Extract plain URLs before escaping so & in query strings is preserved
    const urls = [];
    let urlIndex = 0;
    html = html.replace(/(^|[\s])((?:https?|file):\/\/[^\s]+)/gm, (match, prefix, url) => {
        urls.push(url);
        return prefix + `\x00URL${urlIndex++}\x00`;
    });

    html = html.replace(/&/g, '&amp;')
                .replace(/</g, '&lt;')
                .replace(/>/g, '&gt;');

    html = html.replace(/^### (.*?)$/gm, '<h3>$1</h3>');
    html = html.replace(/^## (.*?)$/gm, '<h2>$1</h2>');
    html = html.replace(/^# (.*?)$/gm, '<h1>$1</h1>');

    // Bold and italic (order matters!)
    html = html.replace(/\*\*\*(.*?)\*\*\*/g, '<b><i>$1</i></b>');
    html = html.replace(/\*\*(.*?)\*\*/g, '<b>$1</b>');
    html = html.replace(/\*(.*?)\*/g, '<i>$1</i>');
    html = html.replace(/(^|[^A-Za-z0-9_])___([^\n]+?)___(?![A-Za-z0-9_])/g, '$1<b><i>$2</i></b>');
    html = html.replace(/(^|[^A-Za-z0-9_])__([^\n]+?)__(?![A-Za-z0-9_])/g, '$1<b>$2</b>');
    html = html.replace(/(^|[^A-Za-z0-9_])_([^\n]+?)_(?![A-Za-z0-9_])/g, '$1<i>$2</i>');

    html = html.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2">$1</a>');

    html = html.replace(/^\* (.*?)$/gm, '<li>$1</li>');
    html = html.replace(/^- (.*?)$/gm, '<li>$1</li>');
    html = html.replace(/^\d+\. (.*?)$/gm, '<li>$1</li>');

    html = html.replace(/(<li>[\s\S]*?<\/li>\s*)+/g, function(match) {
        return '<ul>' + match + '</ul>';
    });

    html = html.replace(/\x00URL(\d+)\x00/g, (_, index) => {
        const url = urls[parseInt(index)];
        const display = url.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
        return `<a href="${url}">${display}</a>`;
    });

    // Restore code blocks and inline code BEFORE line break processing
    html = html.replace(/\x00CODEBLOCK(\d+)\x00/g, (match, index) => {
        return codeBlocks[parseInt(index)];
    });

    html = html.replace(/\x00INLINECODE(\d+)\x00/g, (match, index) => {
        return inlineCode[parseInt(index)];
    });

    html = html.replace(/\n\n/g, '</p><p>');
    html = html.replace(/\n/g, '<br/>');

    if (!html.startsWith('<')) {
        html = '<p>' + html + '</p>';
    }

    html = html.replace(/<br\/>\s*<pre>/g, '<pre>');
    html = html.replace(/<br\/>\s*<ul>/g, '<ul>');
    html = html.replace(/<br\/>\s*<h[1-6]>/g, '<h$1>');

    html = html.replace(/<p>\s*<\/p>/g, '');
    html = html.replace(/<p>\s*<br\/>\s*<\/p>/g, '');

    html = html.replace(/(<br\/>){3,}/g, '<br/><br/>');
    html = html.replace(/(<\/p>)\s*(<p>)/g, '$1$2');

    html = html.trim();

    return html;
}
