// Browser half: execute EpubCFI and sanitizer extracted from installed Zotero.
const fs = require('node:fs');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
(async () => {
    const browser = await chromium.launch({ executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: true });
    try {
        const page = await browser.newPage();
        await page.addScriptTag({ content: fs.readFileSync(process.argv[2], 'utf8') });
        const source = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'));
        const result = await page.evaluate(async ({ chapters, cases, range_text }) => {
            const containers = [];
            for (const xhtml of chapters) {
                const container = document.createElement('div');
                container.className = 'cfi-stop'; document.body.append(container);
                await Oracle.sanitizeAndRender(xhtml, { container, cssRewriter: {
                    add: async () => 'fixture-css', addByURL: async () => '',
                    trackedSelectors: { table: [], sup: [], sub: [], breakBefore: [], breakAfter: [], writingMode: [] },
                }});
                containers.push(container);
            }
            const incoming = [];
            for (const entry of cases) {
                const container = containers[entry.section];
                const node = container.querySelector(entry.selector).childNodes[entry.child || 0];
                const range = new Oracle.EpubCFI(entry.cfi).toRange(document, undefined, container);
                if (range.startContainer !== node || range.startOffset !== entry.offset) throw Error('Outbound passage mismatch: ' + entry.cfi);
                const expected = document.createRange(); expected.setStart(node, entry.offset); expected.collapse(true);
                incoming.push(new Oracle.EpubCFI(expected, '/6/' + (2 * entry.spine) + '[chap' + (entry.section + 1) + ']').toString());
            }
            const start = new Oracle.EpubCFI(cases[2].cfi).toRange(document, undefined, containers[0]);
            const end = new Oracle.EpubCFI(cases[3].cfi).toRange(document, undefined, containers[0]);
            start.setEnd(end.startContainer, end.startOffset);
            if (start.toString() !== range_text) throw Error('Highlight passage mismatch: ' + start.toString());
            return incoming;
        }, source);
        fs.writeFileSync(process.argv[4], JSON.stringify(result));
        console.log('ZOTERO POSITION ORACLE PASS: ' + result.length + ' points and 1 range');
    } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
