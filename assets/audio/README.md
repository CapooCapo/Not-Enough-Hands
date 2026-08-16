# Sound effects

Licenses are recorded per file below. Attribution is not required for the CC0
or Pixabay-licensed files, but their sources are kept here for project
provenance.

- `statue_teleport.wav` — “Teleport” by fins, submitted by diligentcircle:
  https://opengameart.org/content/teleport
- `statue_attack.ogg` — “Scary High-pitched Ghost” by Fupi:
  https://opengameart.org/content/scary-high-pitched-ghost
- `417537__danthaiwang__scratching-with-fingernails.wav` — “Scratching with
  Fingernails” by danthaiwang:
  https://freesound.org/people/danthaiwang/sounds/417537/
- `statue_spotted_jumpscare.mp3` — “Jump scare sound 2” by dangthaiduy007
  (CC0):
  https://freesound.org/people/dangthaiduy007/sounds/341669/
- `creature_reveal.mp3` — “Creature Reveal” by Universfield (Pixabay Content
  License; stored for a future creature and not currently used by a scene):
  https://pixabay.com/sound-effects/horror-creature-reveal-143028/
- `536770__doctorphil__footsteps-on-a-wooden-floor.wav` — “Footsteps on a
  Wooden Floor” by doctorphil (CC0):
  https://freesound.org/people/doctorphil/sounds/536770/
- `ambient_house_tone.mp3` — “Roomtone Bedroom Yew” by leonelmail (CC0):
  https://freesound.org/people/leonelmail/sounds/329569/
- `ambient_window_wind.mp3` — “Window Wind” by unfa (CC0):
  https://freesound.org/people/unfa/sounds/174501/
- `ambient_distant_night.mp3` — “Countryside at the Night Crickets” by
  Martin.Sadoux (CC0):
  https://freesound.org/people/Martin.Sadoux/sounds/422582/
- `house_creak_single.mp3` — “Wood Creak Single V3” by Rudmer_Rotteveel
  (CC0):
  https://freesound.org/people/Rudmer_Rotteveel/sounds/502511/
- `house_creaks_slow.mp3` — “Slow Wooden Creaks x5” by peridactyloptrix
  (CC0):
  https://freesound.org/people/peridactyloptrix/sounds/218163/
- `house_floor_creaks.mp3` — “Floor Creak Hardwood, Old House” by TRP
  (CC0):
  https://freesound.org/people/TRP/sounds/715636/
- `crawler_bone_snap.wav` — “Deep Bone Crack/Break SFX” by Zane Little Music
  (CC0), one file from the pack. Played by the crawler every time it re-grips
  a new surface:
  https://opengameart.org/content/deep-bone-crackbreak-sfx
- `crawler_chitter.ogg` — “80 CC0 creature SFX” by rubberduck (CC0), the
  `bug_09` file. The crawler's lurking/listening vocalisation:
  https://opengameart.org/content/80-cc0-creture-sfx-2
- `crawler_breath.ogg` — “80 CC0 creature SFX” by rubberduck (CC0), the
  `breath` file. Only audible within a few metres of the crawler:
  https://opengameart.org/content/80-cc0-creature-sfx
- `crawler_scream.ogg` — “80 CC0 creature SFX” by rubberduck (CC0), the
  `scream_01` file. The pounce:
  https://opengameart.org/content/80-cc0-creature-sfx

The four `crawler_*` files were picked by name from CC0 packs rather than
auditioned, so they are the most likely thing in the creature to want swapping.
They are plain `AudioStreamPlayer3D` streams in `ghosts/crawler_ghost.tscn` -
replacing a file keeps every behaviour intact. `creature_reveal.mp3` above is
still unused and is a reasonable alternative for the pounce.
