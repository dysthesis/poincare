use nvim_oxi::{
    api::{self as nvim, opts::OptionOpts},
    conversion::ToObject,
};

pub struct Opt<'a, T>
where
    T: ToObject,
{
    pub opts: OptionOpts,
    pub name: &'a str,
    pub value: T,
}

impl<'a, T> Opt<'a, T>
where
    T: ToObject,
{
    pub fn new(opts: OptionOpts, name: &'a str, value: T) -> Self {
        Self { opts, name, value }
    }

    pub fn set(self) -> () {
        let Self { opts, name, value } = self;
        let res = nvim::set_option_value(name, value, &opts);
        if let Err(e) = &res {
            nvim_oxi::print!("{:?}", e);
        }
    }
}

pub struct Var<'a, T>
where
    T: ToObject,
{
    pub name: &'a str,
    pub value: T,
}

impl<'a, T> Var<'a, T>
where
    T: ToObject,
{
    pub fn set(self) -> () {
        let Self { name, value } = self;
        let r = nvim::set_var(name, value);
        if let Err(e) = &r {
            nvim_oxi::print!("{:?}", e);
        }
    }
}
