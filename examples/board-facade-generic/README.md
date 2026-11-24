# board_facade_generic — yaml-as-is via `TBoardDisplay.Start`

SPI policy is in `esp_mosaico` board yaml / `gen_bmgr_codes`. This demo only
calls `TBoardDisplay.Start` (`DefaultConfig`). See `../../sdk/PROFILES.md`
and `../board-suite/` for the multi-SDK suite.

Build/run under esp32sim: same recipe as `../board-suite/README.md`
(substitute `board_facade_generic`).
