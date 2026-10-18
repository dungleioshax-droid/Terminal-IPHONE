// Polyfill for the broken/incomplete Intl.Segmenter on iOS
// (V8's ICU break iterator data is incomplete in the iOS Node.js build,
// which crashes some AI CLIs). A pure-JS replacement, modelled after the
// community fix that ships with claude-code iOS packages.
//
// Loaded globally by the node wrapper: node -r segmenter-shim.js ...
/* eslint-disable */
(function () {
	'use strict';
	if (
		typeof Intl === 'undefined' ||
		!Intl.Segmenter ||
		(() => {
			try {
				// Exercise the iterator: crashes / throws on the broken iOS build.
				const seg = new Intl.Segmenter('en', { granularity: 'word' });
				for (const _ of seg.segment('hello world'));
				return false;
			} catch (_) {
				return true;
			}
		})()
	) {
		return; // healthy host or no Intl at all — leave it alone.
	}

	class SimpleSegmenter {
		constructor(locale, options) {
			this.locale = locale;
			this.granularity = (options && options.granularity) || 'grapheme';
		}

		segment(str) {
			const out = [];
			if (this.granularity === 'word') {
				let match;
				const rx = /(\s+)|([^\s]+)/g;
				while ((match = rx.exec(str)) !== null) {
					out.push({
						segment: match[0],
						index: match.index,
						isWordLike: match[2] !== undefined
							? match[2].length > 0
							: undefined,
					});
				}
			} else if (this.granularity === 'sentence') {
				const rx = /[^.!?]*[.!?]+(?:\s|$)/g;
				let last = 0;
				let match;
				while ((match = rx.exec(str)) !== null) {
					out.push({ segment: match[0], index: match.index });
					last = match.index + match[0].length;
				}
				if (last < str.length) {
					out.push({ segment: str.slice(last), index: last });
				}
			} else {
				// grapheme: treat base + combining marks together.
				let match;
				const rx = /\S(?:[\u0300-\u036f\u0483-\u0489\u0591-\u05bd\u0610-\u061a\u064b-\u065f\u06d6-\u06dc\u0e00-\u0e3a\u1ab0-\u1aff\u1dc0-\u1dff\u20d0-\u20f0\ufe00-\ufe0f])*|\s+|[^\s\S]/g;
				while ((match = rx.exec(str)) !== null) {
					out.push({ segment: match[0], index: match.index });
				}
			}
			return {
				[Symbol.iterator]() {
					return out[Symbol.iterator]();
				},
				segments: out,
			};
		}

		resolvedOptions() {
			return { locale: this.locale, granularity: this.granularity };
		}
	}

	Intl.Segmenter = SimpleSegmenter;
})();
