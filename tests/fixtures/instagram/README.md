# Instagram detector fixtures

These small JPEG crops come from the kjfo_od profile screenshot supplied with
this bug report. They cover two menu boards, a food photo, and a sandwich ad.
They are test-only assets, not published under docs/.

The detector intentionally targets the current peach/red/blue board layout.
When that layout changes, add a representative fixture before changing its
thresholds. Color coverage alone is insufficient; the negative fixtures must
continue to be rejected.
