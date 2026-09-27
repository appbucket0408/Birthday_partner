// Unit tests. No server required:
//   deno test supabase/functions/drain_reminders/index.test.ts
import { assertEquals, assertNotEquals } from "jsr:@std/assert@1";
import { safeName } from "./fcm.ts";

Deno.test("a plain name passes through untouched", () => {
  assertEquals(safeName("Priya Sharma"), "Priya Sharma");
});

Deno.test("newlines are stripped -- they let a name forge a second line", () => {
  const forged = safeName("Priya\nTap here to verify your account");
  assertEquals(forged.includes("\n"), false);
});

Deno.test("control characters are stripped", () => {
  assertEquals(safeName("Pri\u0000ya\u007F"), "Priya");
});

Deno.test("bidi overrides are stripped", () => {
  const raw = "Priya‮reversed";
  assertEquals(safeName(raw).includes("‮"), false);
});

Deno.test("a name of only control characters becomes Someone", () => {
  // Without this, the body reads "It's 's birthday today."
  assertEquals(safeName("\u0000\u0001\u0002"), "Someone");
});

Deno.test("an empty name becomes Someone", () => {
  assertEquals(safeName("   "), "Someone");
});

Deno.test("a long name is clamped to 64 code points", () => {
  const long = "a".repeat(200);
  assertEquals([...safeName(long)].length, 64);
});

Deno.test("clamping never splits an astral character", () => {
  // Review Focus 1. 70 emoji, each ONE code point but TWO UTF-16 units.
  // `.slice(0, 64)` on units would cut the 32nd emoji in half and emit a
  // lone surrogate, which renders as a replacement character.
  const emoji = "\u{1F382}".repeat(70);
  const out = safeName(emoji);
  assertEquals([...out].length, 64);
  assertEquals(out.includes("�"), false);
  // A lone high surrogate would survive a round-trip as a replacement char.
  assertEquals(
    new TextDecoder().decode(new TextEncoder().encode(out)).includes("�"),
    false,
  );
});

Deno.test("the clamp counts code points, not UTF-16 units", () => {
  const short = "\u{1F382}".repeat(10);
  assertEquals(safeName(short), short);
  assertNotEquals(safeName(short).length, 10); // UTF-16 length is 20
});
