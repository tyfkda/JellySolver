import { DefaultRubyVM } from 'https://cdn.jsdelivr.net/npm/@ruby/wasm-wasi@2.7.0/dist/browser/+esm'

const WASM_PATH = './jelly-solver.wasm'

const RUBY_CODE = `
require 'js'
require_relative 'lib/solver'
require_relative 'lib/stage_parser'

class Accessor
    def load_stage(fn)
        fn = fn.to_s  # JSから文字列を受け取る場合、これが必要
        stage = File.open(fn) do |f|
            stage_parser = Jelly::StageParser.new()
            stage_parser.parse(f)
        end
        return stage
    end

    def solve(stage)
        solver = Jelly::Solver.new(quiet: true)
        moves = solver.solve(stage.dup())

        return nil if moves.nil?

        result = []
        moves.each do |move|
            result << [stage.make_lines(), move]
            jelly = stage.jellies.find {|it| it.occupy_position?(move[0], move[1])}
            stage = Jelly::Solver.move_jelly(stage, jelly, move[2])
        end
        result << [stage.make_lines(), nil]
        return result
    end
end
Accessor.new()
`

class MyWorker {
    constructor() {
        this.messageHandler = {
            initialize: async (_data, sendResponse) => {
                try {
                    await this.initialize()
                    sendResponse({ maxStageNo: 70 })  // TODO: ファイルから最大ステージ数を調べる
                } catch (e) {
                    sendResponse({ error: e.toString() })
                }
            },
            loadStage: (data, sendResponse) => {
                this.stage = this.loadStage(data.stageNo)
                sendResponse({ stage: this.stage.call('make_lines').toJS() })
            },
            solve: async (_data, sendResponse) => {
                const solution = await this.solveStage(this.stage)
                sendResponse({ solution })
            },
        }

        self.addEventListener('message', async (event) => {
            const data = event.data
            const type = data.type
            const handler = this.messageHandler[type]
            if (handler != null) {
                handler(data, (response) => self.postMessage({ type: `${type}Done`, ...response }))
            } else {
                console.log('no handler for', data)
            }
        })
    }

    async initialize() {
        const response = await fetch(WASM_PATH)
        if (!response.ok)
            throw new Error(`HTTP error! status: ${response.status}, path=${WASM_PATH}`)
        const module = await WebAssembly.compileStreaming(response)
        const { vm } = await DefaultRubyVM(module)
        this.vm = vm
        this.accessor = this.vm.eval(RUBY_CODE)
    }

    loadStage(stageNo) {
        const fn = `stagedata/${stageNo.toString().padStart(3, '0')}.txt`
        return this.accessor.call('load_stage', this.vm.wrap(fn))
    }

    async solveStage(stage) {
        const result = this.accessor.call('solve', stage).toJS()
        return result
    }
}

/*const worker =*/ new MyWorker()
