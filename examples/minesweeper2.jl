using Compat # for Nullable
using Colors
using Lazy

#### Model ####

@defonce immutable Board{lost}
    uncovered::AbstractMatrix
    mines::AbstractMatrix
    squaresleft::Int64
end

const BLANK = -1
const BLANKFLAG = -2
const FLAGDELTA = -1

function newboard(m, n, minefraction=0.05)
    mines = rand(m,n) .< minefraction
    Board{false}(fill(BLANK, (m,n)), mines, n*m-sum(mines))
end

function squares_around(mines, i, j)
    m, n = size(mines)

    a = max(1, i-1)
    b = min(i+1, m)
    c = max(1, j-1)
    d = min(j+1, n)

    return (a,b,c,d)
end

function mines_around(board, i, j)
    a,b,c,d = squares_around(board.mines, i, j)
    sum(board.mines[a:b, c:d])
end

clear_around!(board, uncovered, i, j) = begin
    a,b,c,d = squares_around(board.mines, i, j)
    ncleared = 0
    for row = a:b, col = c:d
        uncovered[row,col] >= 0 && continue;
        uncovered[row,col] = mines_around(board,row,col)
        if uncovered[row,col] == 0
            ncleared += clear_around!(board, uncovered, row, col)
        end
        ncleared += 1
    end
    ncleared
end

### Update ###

next(board::Board{true}, move) = board

toggleflag(number) = number == BLANK ? BLANKFLAG : number == BLANKFLAG ? BLANK : number

function next(board, move)
    i, j, clickinfo = move
    if get(clickinfo) == Escher.RightButton()
        uncovered = copy(board.uncovered)
        uncovered[i,j] = toggleflag(uncovered[i,j])
        return Board{false}(uncovered, board.mines, board.squaresleft)
    else # Escher.LeftButton() was pressed
        if board.mines[i, j]
            return Board{true}(board.uncovered, board.mines, board.squaresleft) # Game over
        else
            uncovered = copy(board.uncovered)
            if uncovered[i, j] < 0
                uncovered[i, j] = mines_around(board, i, j)
                ncleared = 1
                if uncovered[i, j] == 0
                    ncleared += clear_around!(board, uncovered, i, j)
                end
                return Board{false}(uncovered, board.mines, board.squaresleft-ncleared)
            else
                return Board{false}(uncovered, board.mines, board.squaresleft)
            end
        end
    end
end

const ClickT = Nullable{Escher.MouseButton}
moves_signal = Input{Tuple{Int,Int,ClickT}}((0, 0, nothing))
initial_board_signal = Input{Board}(newboard(10, 10))
board_signal = flatten(
    lift(initial_board_signal) do b
        foldl(next, b, moves_signal; typ=Board)
    end
)

### View ###


colors = ["#fff", colormap("reds", 7)]

box(content, color) =
    inset(Escher.middle,
        fillcolor(color, size(4em, 4em, empty)),
        Escher.fontsize(2em, content)) |> paper(1) |> Escher.pad(0.2em)

isflagged(x) = x == BLANKFLAG
getcolor(x) = isflagged(x) ? colors[1] : colors[x+2]
number(x) = box(x < 0 ? isflagged(x) ? icon("flag") : "" : string(x) |> fontweight(800), getcolor(x))
mine = box(icon("report"), "#e58")
block(board::Board{true}, i, j) =
    board.mines[i, j] ? mine :
        number(board.uncovered[i, j])

block(board, i, j) = begin
    clicksig = Input{ClickT}(nothing)
    block_view = clickable([leftbutton, rightbutton], number(board.uncovered[i, j]))
    lift(clicksig; init=nothing) do clickinfo
        Timer(t->push!(moves_signal, (i,j,clickinfo)), 0.02)
        nothing
    end
    block_view >>> clicksig
end

gameover = vbox(
        title(2, "Game Over!") |> Escher.pad(1em),
        addinterpreter(_ -> newboard(10, 10), button("Start again")) >>> initial_board_signal
    ) |> Escher.pad(1em) |> fillcolor("white")

gamewon = vbox(
        title(2, "Game Won!") |> Escher.pad(1em),
        addinterpreter(_ -> newboard(10, 10), button("Start again")) >>> initial_board_signal
    ) |> Escher.pad(1em) |> fillcolor("white")

function showboard{lost}(board::Board{lost})
    m, n = size(board.mines)
    b = hbox([vbox([block(board, i, j) for j in 1:m]) for i in 1:n])
    if lost
        inset(Escher.middle, b, gameover)
    else
       board.squaresleft > 0 ? b : inset(Escher.middle, b, gamewon)
   end
end

function main(window)
    push!(window.assets, "widgets")
    push!(window.assets, "icons")

    vbox(
       vskip(2em),
       title(3, "minesweeper2"),
       vskip(2em),
       consume(showboard, board_signal, typ=Tile),
       vskip(2em)
    ) |> packacross(center)
end
