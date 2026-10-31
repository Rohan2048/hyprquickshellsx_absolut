.pragma library

function playExit(ctx) {
    ctx.entranceSlide.stop(); ctx.entranceFade.stop(); ctx.entranceProgress.stop()
    ctx.exitSlide.start(); ctx.exitFade.start(); ctx.exitProgress.start()
}
