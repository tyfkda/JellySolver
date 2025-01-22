function renderStage(stage, move) {
    const canvas = document.getElementById('canvas')
    const width = canvas.width
    const height = canvas.height
    const ctx = canvas.getContext('2d')
    ctx.clearRect(0, 0, canvas.width, canvas.height)
    const h = stage.length, w = stage[0].length
    const ux = width / w, uy = height / h
    for (let i = 0; i < h; ++i) {
        const line = stage[i]
        const y = i * uy
        for (let j = 0; j < w; ++j) {
            const x = j * ux
            let color = null
            switch (line[j]) {
            case '.': color = '#aee'; break
            case '#': color = '#500'; break
            case 'R': case 'r': color = '#f00'; break
            case 'G': case 'g': color = '#0f0'; break
            case 'B': case 'b': color = '#00f'; break
            case 'Y': case 'y': color = '#ee0'; break
            case '@': color = '#280000'; break
            case '*': color = '#002800'; break
            case '$': color = '#000028'; break
            case '%': color = '#280028'; break
            }
            if (color != null) {
                ctx.fillStyle = color
                ctx.fillRect(x, y, ux, uy)
            }
        }
    }

    if (move != null) {
        const [x, y, dx] = move
        ctx.fillStyle = '#fff'
        ctx.font = '20px sans-serif'
        ctx.textAlign = 'center'
        ctx.textBaseline = 'middle'
        ctx.fillText('←→'[(dx + 1) >> 1], (x + 0.5) * ux, (y + 0.5) * uy)
    }
}

let worker
const messageHandler = {}

window.initialData = {
    error: null,
    stageNo: 1,
    maxStageNo: 1,
    solving: false,
    step: 0,
    solution: null,
    elapsedTime: null,

    async init() {
        worker = new Worker('worker.js', { type: 'module' })

        worker.addEventListener('message', (event) => {
            const data = event.data

            const type = data.type
            const handler = messageHandler[type]
            if (handler != null) {
                handler(data)
            } else {
                console.log('no handler for', data)
            }
        })

        this.postMessageToWorker('initialize', {}, (data) => {
            if (data.error) {
                console.error(data.error)
                this.error = data.error
                return
            }

            this.maxStageNo = data.maxStageNo
            this.setStageNo(this.stageNo)
        })
    },

    prevStage() {
        if (this.stageNo > 1)
            this.setStageNo(this.stageNo - 1)
    },

    nextStage() {
        if (this.stageNo < this.maxStageNo)
            this.setStageNo(this.stageNo + 1)
    },

    solve() {
        this.solving = true
        this.solution = null
        this.elapsedTime = null
        const startTime = performance.now()
        this.postMessageToWorker('solve', {}, (data) => {
            const endTime = performance.now()
            this.solving = false
            this.solution = data.solution
            this.elapsedTime = `${Math.round(endTime - startTime) / 1000}秒`
            this.setStep(0)
        })
    },

    prevStep() {
        if (this.step > 0)
            this.setStep(this.step - 1)
    },

    nextStep() {
        if (this.step < this.solution.length - 1)
            this.setStep(this.step + 1)
    },

    setStageNo(stageNo) {
        this.stageNo = stageNo
        this.solving = false
        this.solution = null
        this.elapsedTime = null
        this.postMessageToWorker('loadStage', {stageNo: this.stageNo}, (data) => {
            renderStage(data.stage, null)
        })
    },

    setStep(step) {
        this.step = step
        const [stage, move] = this.solution[step]
        renderStage(stage, move)
    },

    postMessageToWorker(type, data, callback) {
        messageHandler[`${type}Done`] = callback

        worker.postMessage({ type, ...data })
    },
}
