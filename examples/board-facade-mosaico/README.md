# board_facade_mosaico — yaml-as-is + optional CO5300 brightness

Same `TBoardDisplay.Start` path as `board-facade-generic`, plus
`MosaicoSetBrightness` (the only remaining Pascal board helper). SPI
80 MHz / `psram_dma_direct` are not set in Pascal.

See `../../sdk/PROFILES.md` and `../board-suite/`.
