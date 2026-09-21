import Foundation

extension HTMLRenderer {

    /// The stylesheet for printed and exported output.
    ///
    /// Print is not the screen: it is always light, it has physical page breaks
    /// worth respecting, and hyperlinks lose their meaning unless the URL is
    /// visible. Exported HTML keeps the screen affordances instead.
    static func stylesheet(forPrint: Bool) -> String {
        var css = """
        @page {
          margin: 20mm 18mm;
        }

        :root {
          --text: #16181d;
          --muted: #5c6370;
          --rule: #dfe2e8;
          --accent: #1f4fa8;
          --code-bg: #f6f7f9;
          --code-text: #8a2450;
          --quote-bar: #d3d8e0;
          --mark: #ffe89e;
        }

        * { box-sizing: border-box; }

        html {
          -webkit-text-size-adjust: 100%;
        }

        body {
          margin: 0;
          color: var(--text);
          background: #ffffff;
          font-family: -apple-system, "SF Pro Text", "Helvetica Neue", Helvetica, Arial, sans-serif;
          font-size: 11.5pt;
          line-height: 1.55;
          -webkit-font-smoothing: antialiased;
        }

        .doctor-document {
          max-width: 46em;
          margin: 0 auto;
          padding: 0;
        }

        /* --- Headings ------------------------------------------------------- */

        h1, h2, h3, h4, h5, h6 {
          line-height: 1.25;
          margin: 1.6em 0 0.6em;
          font-weight: 600;
          break-after: avoid-page;
          page-break-after: avoid;
        }

        h1 { font-size: 2.0em; font-weight: 700; margin-top: 0; letter-spacing: -0.015em; }
        h2 { font-size: 1.5em; font-weight: 700; letter-spacing: -0.01em; }
        h3 { font-size: 1.25em; }
        h4 { font-size: 1.1em; }
        h5 { font-size: 1em; }
        h6 { font-size: 1em; color: var(--muted); }

        h1 + *, h2 + *, h3 + * { margin-top: 0; }

        /* --- Text ----------------------------------------------------------- */

        p { margin: 0 0 0.85em; orphans: 2; widows: 2; }

        a { color: var(--accent); text-decoration: none; border-bottom: 1px solid rgba(31, 79, 168, 0.35); }

        strong { font-weight: 650; }
        em { font-style: italic; }
        del { color: var(--muted); }
        mark { background: var(--mark); padding: 0 0.15em; border-radius: 2px; }

        .wikilink {
          color: var(--accent);
          border-bottom: 1px dotted rgba(31, 79, 168, 0.5);
        }

        hr {
          border: 0;
          border-top: 1px solid var(--rule);
          margin: 2em 0;
        }

        /* --- Lists ---------------------------------------------------------- */

        ul, ol { margin: 0 0 0.85em; padding-left: 1.5em; }
        li { margin: 0.15em 0; }
        li > p { margin: 0; }
        li.loose > p, .loose > li > p { margin: 0 0 0.6em; }
        ul ul, ul ol, ol ul, ol ol { margin-bottom: 0; }

        ul.task-list { list-style: none; padding-left: 1.2em; }
        ul.task-list > li.task { position: relative; }
        li.task input[type="checkbox"] {
          margin-right: 0.45em;
          vertical-align: baseline;
        }

        /* --- Code ----------------------------------------------------------- */

        code, kbd, samp {
          font-family: "SF Mono", ui-monospace, Menlo, Monaco, "Courier New", monospace;
          font-size: 0.88em;
        }

        p code, li code, td code, th code, h1 code, h2 code, h3 code, h4 code {
          background: var(--code-bg);
          color: var(--code-text);
          padding: 0.12em 0.32em;
          border-radius: 3px;
        }

        pre {
          background: var(--code-bg);
          border: 1px solid var(--rule);
          border-radius: 6px;
          padding: 0.85em 1em;
          margin: 0 0 1em;
          overflow-x: auto;
          white-space: pre-wrap;
          word-wrap: break-word;
          break-inside: avoid-page;
          page-break-inside: avoid;
        }

        pre code {
          background: none;
          color: var(--text);
          padding: 0;
          font-size: 0.85em;
          line-height: 1.5;
        }

        pre.frontmatter {
          background: none;
          border: 0;
          border-left: 2px solid var(--rule);
          border-radius: 0;
          color: var(--muted);
          font-size: 0.8em;
          padding: 0.2em 0 0.2em 0.9em;
          margin-bottom: 1.6em;
        }

        /* --- Quotes --------------------------------------------------------- */

        blockquote {
          margin: 0 0 1em;
          padding: 0.1em 0 0.1em 1.1em;
          border-left: 3px solid var(--quote-bar);
          color: var(--muted);
        }

        blockquote > :last-child { margin-bottom: 0; }

        /* --- Tables --------------------------------------------------------- */

        table {
          border-collapse: collapse;
          width: 100%;
          margin: 0 0 1.2em;
          font-size: 0.95em;
          break-inside: avoid-page;
          page-break-inside: avoid;
        }

        th, td {
          border: 1px solid var(--rule);
          padding: 0.42em 0.7em;
          text-align: left;
          vertical-align: top;
        }

        thead th {
          background: var(--code-bg);
          font-weight: 650;
        }

        /* --- Media ---------------------------------------------------------- */

        img {
          max-width: 100%;
          height: auto;
          break-inside: avoid-page;
        }

        """

        if forPrint {
            css += """

            /* Printed links lose their destination unless we say it out loud —
               but only for external URLs, and never for in-page anchors. */
            @media print {
              a[href^="http"]::after {
                content: " (" attr(href) ")";
                font-size: 0.78em;
                color: var(--muted);
                word-break: break-all;
              }
              a { border-bottom: 0; }
            }
            """
        } else {
            css += """

            body { padding: 3em 1.5em 6em; }

            @media (prefers-color-scheme: dark) {
              :root {
                --text: #dde0e6;
                --muted: #949cab;
                --rule: #343841;
                --accent: #79aefb;
                --code-bg: #1e2127;
                --code-text: #ed9eb5;
                --quote-bar: #454b57;
                --mark: #6b5a1f;
              }
              body { background: #16181c; }
              thead th { background: #232830; }
            }
            """
        }

        return css
    }
}
