mod consts;
mod point;
mod jelly_shape;
mod jelly;
mod stage;
mod parser;
mod solver;

use stage::Stage;
use solver::{Solver, Move};

fn disp_stage(stage: &Stage) {
    let lines = stage.make_lines();
    for line in lines {
        println!("{}", line);
    }
}

fn disp_solution(mut stage: Stage, moves: &[Move]) {
    disp_stage(&stage);
    for m in moves {
        println!("{}", m.to_string());
        let jelly_id = stage.jellies.iter()
            .find(|j| j.occupy_position(m.x, m.y))
            .map(|j| j.id);

        let j_id = match jelly_id {
            Some(id) => id,
            None => panic!("Jelly not found for move: {:?}", m),
        };

        let next_stage = Solver::move_jelly_static(&stage, stage.find_jelly_by_id(j_id).unwrap(), m.dx);
        stage = match next_stage {
            Some(s) => s,
            None => panic!("Invalid move: {:?}", m),
        };
        disp_stage(&stage);
    }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let mut no_prune = false;
    let mut use_bfs = false;
    let mut quiet = false;
    let mut parallel = false;
    let mut filename = None;

    for arg in args.iter().skip(1) {
        if arg == "--no-prune" {
            no_prune = true;
        } else if arg == "--bfs" {
            use_bfs = true;
        } else if arg == "--quiet" {
            quiet = true;
        } else if arg == "--parallel" {
            parallel = true;
        } else if arg.starts_with('-') {
            eprintln!("Unknown option: {}", arg);
            std::process::exit(1);
        } else {
            filename = Some(arg.clone());
        }
    }

    let filename = match filename {
        Some(f) => f,
        None => {
            eprintln!("Usage: rust_jelly_solver [--no-prune] [--bfs] [--quiet] [--parallel] <stage_file>");
            std::process::exit(1);
        }
    };

    let file = match std::fs::File::open(&filename) {
        Ok(f) => f,
        Err(e) => {
            eprintln!("Failed to open file: {} ({})", filename, e);
            std::process::exit(1);
        }
    };

    let parser = parser::StageParser;
    let stage = match parser.parse(file) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("Failed to parse file: {} ({})", filename, e);
            std::process::exit(1);
        }
    };

    let mut solver = Solver::new(no_prune, use_bfs, quiet, parallel);
    let start_time = std::time::Instant::now();
    let moves = solver.solve(stage.clone());
    let elapsed = start_time.elapsed().as_secs_f64();

    if let Some(moves_list) = moves {
        if !quiet {
            disp_solution(stage, &moves_list);
        }
        println!("Steps={}, check={}, elapsed={:.3}s", moves_list.len(), solver.check_count(), elapsed);
    } else {
        println!("No solution found. check={}, elapsed={:.3}s", solver.check_count(), elapsed);
    }
}
