.pragma library

function playEntrance(ctx) {
    ctx.exitSlide.stop(); ctx.exitFade.stop(); ctx.exitProgress.stop()
    ctx.entranceSlide.start(); ctx.entranceFade.start(); ctx.entranceProgress.start()
}
