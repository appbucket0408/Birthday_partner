// Everything in drain_reminders that has logic worth testing. index.ts stays
// transport and orchestration only.

/// C0 and C1 control characters. Newlines are the dangerous ones: they let a
/// display_name forge what looks like a second line of app-authored text.
const CONTROL = /[\u0000-\u001F\u007F-\u009F]/g;

/// Unicode bidirectional overrides and isolates. These let a name visually
/// reorder the sentence it is interpolated into without changing a byte of
/// the surrounding template.
const BIDI = /[‪-‮⁦-⁩]/g;

const MAX_NAME_POINTS = 64;

/// people.display_name is free text the user chooses, and
/// 20260824000005_device_tokens.sql documents the reachable attack: an
/// attacker who obtains a device token reassigns it to their own account,
/// creates a celebrated person whose display_name is arbitrary text with a
/// birthday of today, and the pipeline delivers that text to the victim's
/// device as a trusted notification.
///
/// This narrows the class; it does not close it. A short, plain, printable
/// name can still read as a sentence. Closing that needs a title/body split
/// that never interpolates into app-authored prose -- spec section 10.1.
export function safeName(raw: string): string {
  const stripped = raw.replace(CONTROL, "").replace(BIDI, "").trim();
  // Spread iterates CODE POINTS. `.slice(0, 64)` on the string would work on
  // UTF-16 units and cut an emoji or a Devanagari cluster in half, emitting a
  // lone surrogate.
  const points = [...stripped];
  const clamped = points.length > MAX_NAME_POINTS
    ? points.slice(0, MAX_NAME_POINTS).join("")
    : stripped;
  const final = clamped.trim();
  return final === "" ? "Someone" : final;
}

export function reminderBody(name: string, offsetDays: number): string {
  const safe = safeName(name);
  if (offsetDays === 0) return `It's ${safe}'s birthday today.`;
  if (offsetDays === 1) return `${safe}'s birthday is tomorrow.`;
  return `${safe}'s birthday is in ${offsetDays} days.`;
}
