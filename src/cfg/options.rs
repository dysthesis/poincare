use crate::api::{self, Opt};
use nvim_oxi::api::opts::OptionOpts;

pub fn options() {
    let options: [Opt<bool>; 3] = [
        Opt {
            opts: OptionOpts::default(),
            name: "termguicolors",
            value: true,
        },
        Opt {
            opts: OptionOpts::default(),
            name: "number",
            value: true,
        },
        Opt {
            opts: OptionOpts::default(),
            name: "relativenumber",
            value: true,
        },
    ];

    options.into_iter().for_each(Opt::set);
}
