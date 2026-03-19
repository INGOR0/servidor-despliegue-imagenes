const el = document.getElementById('countdown')
if (el) {
    let seconds = parseInt(el.dataset.seconds)
    const update = () => {
        if (seconds <= 0) {
            el.closest('p').textContent = 'Puedes intentarlo de nuevo.'
            return
        }
        const minutes = Math.floor(seconds / 60)
        const secs = seconds % 60
        el.textContent = `Espera ${minutes}:${secs.toString().padStart(2, '0')}`
        seconds--
        setTimeout(update, 1000)
    }
    update()
}