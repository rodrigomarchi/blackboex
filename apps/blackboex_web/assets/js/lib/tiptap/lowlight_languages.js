/**
 * @file Builds the lowlight registry used by Tiptap code blocks.
 */
import { createLowlight } from "lowlight";
import javascript from "highlight.js/lib/languages/javascript";
import typescript from "highlight.js/lib/languages/typescript";
import python from "highlight.js/lib/languages/python";
import elixir from "highlight.js/lib/languages/elixir";
import ruby from "highlight.js/lib/languages/ruby";
import go from "highlight.js/lib/languages/go";
import rust from "highlight.js/lib/languages/rust";
import java from "highlight.js/lib/languages/java";
import c from "highlight.js/lib/languages/c";
import cpp from "highlight.js/lib/languages/cpp";
import csharp from "highlight.js/lib/languages/csharp";
import php from "highlight.js/lib/languages/php";
import swift from "highlight.js/lib/languages/swift";
import kotlin from "highlight.js/lib/languages/kotlin";
import xml from "highlight.js/lib/languages/xml";
import css from "highlight.js/lib/languages/css";
import scss from "highlight.js/lib/languages/scss";
import json from "highlight.js/lib/languages/json";
import yaml from "highlight.js/lib/languages/yaml";
import sql from "highlight.js/lib/languages/sql";
import graphql from "highlight.js/lib/languages/graphql";
import bash from "highlight.js/lib/languages/bash";
import shell from "highlight.js/lib/languages/shell";
import dockerfile from "highlight.js/lib/languages/dockerfile";
import diff from "highlight.js/lib/languages/diff";
import markdown from "highlight.js/lib/languages/markdown";
import plaintext from "highlight.js/lib/languages/plaintext";

/**
 * Highlight.js language modules exposed to CodeBlockLowlight by language name.
 */
export const LOWLIGHT_LANGUAGES = {
  javascript,
  typescript,
  python,
  elixir,
  ruby,
  go,
  rust,
  java,
  c,
  cpp,
  csharp,
  php,
  swift,
  kotlin,
  html: xml,
  xml,
  css,
  scss,
  json,
  yaml,
  sql,
  graphql,
  bash,
  shell,
  dockerfile,
  diff,
  markdown,
  plaintext,
};

/**
 * Creates a lowlight instance and registers every configured language module.
 * @param {Record<string, Function>} languages - Map of language names to highlight.js language definitions.
 * @returns {object} Lowlight instance consumed by the Tiptap code block extension.
 */
export function buildLowlight(languages = LOWLIGHT_LANGUAGES) {
  const lowlight = createLowlight();
  Object.entries(languages).forEach(([name, language]) =>
    lowlight.register(name, language),
  );
  return lowlight;
}
