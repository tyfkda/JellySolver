# Rubyで優先度付きキューを実装した
# https://gengogo5.com/posts/33
# 比較関数が <=> を返すよう変更、その他メソッド名変更

class PriorityQueue
    # attr_reader :heap

    def initialize(&block)
        # ヒープ配列
        @heap = []

        # 小さい順に優先度が高い
        @comp = block || -> (x, y) { x <=> y }
    end

    def <<(new_one)
        # 新規アイテムを末尾に入れる
        @heap << new_one
        # 末尾から上っていく
        cur = @heap.size - 1

        # ヒープ再構築
        while cur > 0
            # 親ノードの要素番号を取得
            par = (cur - 1) >> 1

            # 追加アイテムより親の方が優先度が高くなったら抜ける
            # = 追加アイテムはcurの位置に収まるのが適切
            break if @comp[@heap[par], new_one] < 0

            # 親の方が優先度が高くなるまで、子に親の値を入れていく
            # 親子入れ替えを行うと計算量が増えるため、子の値を順に上書きして最後に新規アイテムを入れる
            @heap[cur] = @heap[par]
            cur = par
        end
        @heap[cur] = new_one
        self
    end
    alias push <<

    def top
        return nil if @heap.size == 0
        @heap[0]
    end

    def shift
        latest = @heap.pop # 末尾を取り出す
        return latest if @heap.size == 0 # 最後の1個ならそのまま返す

        # 末尾を根に置き換える
        highest = @heap[0]
        @heap[0] = latest

        size = @heap.size
        par = 0
        l = (par << 1) + 1 # 左の子

        while l < size
            r = l + 1 # 右の子

            # 優先度の高い方の子を交換候補にする
            cld = r >= size || @comp[@heap[l], @heap[r]] <= 0 ? l : r

            # 親の方が優先度が高ければ交換をやめる
            break if @comp[latest, @heap[cld]] < 0

            # 子の値を親に入れる
            @heap[par] = @heap[cld]

            # 親
            par = cld
            l = (par << 1) + 1 # 左の子
        end
        # 根に仮置きした値を適切な位置に置く
        @heap[par] = latest
        highest
    end

    def size
        @heap.size
    end
    alias length size

    def empty?
        @heap.empty?
    end

    def clear
        @heap = []
    end
end
