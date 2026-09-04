# The universal foot spellings, so the theme loads on every foot release rather
# than only the newest. Two things changed for that portability, both from
# foot-1.22-only forms that make trixie's foot 1.21 reject the whole config:
#   - the section is [colors], not [colors-dark] ([colors-dark]/[colors-light]
#     are 1.22's own light/dark auto-switching; strapd renders one theme, so the
#     unconditional [colors] is both correct and portable);
#   - the cursor colour is [cursor] color=, not [colors] cursor= (the latter is
#     the newer alias). Order is the same: text-under-cursor, then cursor.
# Both classic forms also apply on the newest foot, so this is strictly wider.
[cursor]
color={{ background_strip }} {{ bright_foreground_strip }}

[colors]
foreground={{ foreground_strip }}
background={{ background_strip }}
selection-foreground={{ selection_foreground_strip }}
selection-background={{ selection_background_strip }}

regular0={{ background_strip }}
regular1={{ red_strip }}
regular2={{ green_strip }}
regular3={{ yellow_strip }}
regular4={{ blue_strip }}
regular5={{ purple_strip }}
regular6={{ cyan_strip }}
regular7={{ foreground_strip }}

bright0={{ muted_strip }}
bright1={{ bright_red_strip }}
bright2={{ bright_green_strip }}
bright3={{ bright_yellow_strip }}
bright4={{ bright_blue_strip }}
bright5={{ bright_magenta_strip }}
bright6={{ bright_cyan_strip }}
bright7={{ bright_foreground_strip }}
