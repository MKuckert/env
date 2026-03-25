set history=32768
filetype plugin on
filetype indent on

set nocompatible
set ruler
set cmdheight=1
set backspace=indent,eol,start

" configure search
set ignorecase
set smartcase
set hlsearch
set incsearch

set showmatch
set magic

set noerrorbells
set novisualbell
set t_vb=
set tm=500

syntax enable
set background=dark
set encoding=utf-8 nobomb

set nobackup
set nowb
set noswapfile

set smarttab
set shiftwidth=4
set tabstop=4
set textwidth=0
set wrapmargin=0

set laststatus=2
set statusline=\ %F%m%r%h\ %w\ \ CWD:\ %r%{getcwd()}%h\ \ \ Line:\ %l\ \ Column:\ %c
