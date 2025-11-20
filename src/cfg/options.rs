use nvim_oxi::api::opts::OptionOpts;

use crate::api::{self, Option};

const DEFAULT_SCOPE: OptionOpts = OptionOpts::builder().build();

const OPTIONS: &[Option<_>] = [
    Option {
        opts: DEFAULT_SCOPE,
        name: "termguicolors",
        value: true,
    },
    Option {
        opts: DEFAULT_SCOPE,
        name: "number",
        value: true,
    },
    Option {
        opts: DEFAULT_SCOPE,
        name: "relativenumber",
        value: true,
    },
];

pub fn options() {
    OPTIONS.iter().for_each(Option::set);
}
