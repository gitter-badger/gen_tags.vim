" ============================================================================
" File: gen_tags.vim
" Author: Jia Sui <jsfaint@gmail.com>
" Description: This file contains some command function for other file.
" ============================================================================

"Global variables
if !exists('g:gen_tags#verbose')
  let g:gen_tags#verbose = 0
endif

"Initial blacklist
if !exists('g:gen_tags#blacklist')
  let g:gen_tags#blacklist = []
endif

"Detect scm type
function! gen_tags#get_scm_type() abort
  let l:scm_list = ['.git', '.hg', '.svn']

  for l:scm in l:scm_list
    let l:dir = finddir(l:scm, '.;')
    if !empty(l:dir)
      return l:scm
    endif
  endfor

  return ''
endfunction

"Find scm repo root
function! gen_tags#find_scm_root() abort
  "Detect scm type
  let l:scm = gen_tags#get_scm_type()
  if empty(l:scm)
    return ''
  endif

  let l:dir = gen_tags#fix_path(finddir(l:scm, '.;'))

  if l:dir ==# l:scm
    return gen_tags#fix_path(getcwd())
  else
    return substitute(l:dir, '/' . l:scm, '', 'g')
  endif
endfunction

"Find the root of the project
"if the project managed by git/hg/svn, return the repo root.
"else return the current work directory.
function! gen_tags#find_project_root() abort
  if !exists('s:project_root')
    let s:project_root = ''
  endif

  let l:scm_root = gen_tags#find_scm_root()
  if !empty(l:scm_root)
    return l:scm_root
  endif

  if empty(s:project_root)
    let s:project_root = gen_tags#fix_path(getcwd())
  endif

  return s:project_root
endfunction

"Prune exit job from job list
function! s:job_prune(cmd) abort
  for l:item in s:job_list
    if a:cmd ==# l:item['cmd']
      let l:index = index(s:job_list, l:item)
      let l:job = l:item
    endif
  endfor

  "Not exist in list, return none
  if !exists('l:job')
    return 'none'
  endif

  let l:job_id = l:job['id']

  let l:status = s:job_status(l:job_id)

  "Remove from list, if job exit
  if l:status ==# 'exit'
    call remove(s:job_list, l:index)
    return 'exit'
  endif
endfunction

function! gen_tags#system_async(cmd, ...) abort
  let l:cmd = a:cmd

  if !exists('s:job_list')
    let s:job_list = []
  endif

  if s:job_prune(l:cmd) ==# 'run'
    call gen_tags#echo('The same job is still running')
    return
  end

  if a:0 == 0
    let l:job_id = s:job_start(l:cmd)
  else
    let l:job_id = s:job_start(l:cmd, a:1)
  endif

  "Record job info
  call add(s:job_list, {'id': l:job_id, 'cmd': l:cmd})
endfunction

"Fix shellslash for windows
function! gen_tags#fix_path(path) abort
  let l:path = expand(a:path, 1)
  if has('win32')
    let l:path = substitute(l:path, '\\', '/', 'g')
  endif

  return l:path
endfunction

"Get db name, remove / : with , beacause they are not valid filename
function! gen_tags#get_db_name(path) abort
  let l:fold = substitute(a:path, '/\|\\\|\ \|:\|\.', '', 'g')
  return l:fold
endfunction

function! gen_tags#echo(str) abort
  if g:gen_tags#verbose
    echomsg a:str
  endif
endfunction

function! s:job_stdout(job_id, data, ...) abort
  if type(a:data) == 1 "string
    call gen_tags#echo(a:data)
  elseif type(a:data) == 3 "list
    for l:item in a:data
      call gen_tags#echo(l:item)
    endfor
  endif
endfunction

function! s:job_start(cmd, ...) abort
  if has('nvim')
    let l:job = {
          \ 'on_stdout': function('s:job_stdout'),
          \ 'on_stderr': function('s:job_stdout'),
          \ }

    if a:0 != 0
      let l:job.on_exit = a:1
    endif

    let l:job_id = jobstart(a:cmd, l:job)
  elseif has('job')
    let l:job = {
          \ 'out_cb': function('s:job_stdout'),
          \ 'err_cb': function('s:job_stdout'),
          \ }

    if a:0 != 0
      let l:job.exit_cb = a:1
    endif

    let l:job_id = job_start(a:cmd, l:job)
  else
    if has('unix')
      let l:cmd = a:cmd . ' &'
    else
      let l:cmd = 'cmd /c start ' . a:cmd
    endif

    call system(l:cmd)
    if a:0 != 0
      call a:1()
    endif

    let l:job_id = -1
  endif

  return l:job_id
endfunction

function! s:job_stop(job_id) abort
  if has('nvim')
    call jobstop(a:job_id)
  elseif has('job')
    call job_stop(a:job_id)
  endif
endfunction

function! s:job_status(job_id) abort
  let l:job_id = a:job_id

  "Check job status
  if has('nvim')
    try
      call jobpid(l:job_id)
      return 'run'
    catch
      return 'exit'
    endtry
  elseif has('job')
    if job_status(l:job_id) ==# 'dead'
      return 'exit'
    else
      return 'run'
    endif
  endif
endfunction

augroup gen_tags
  au!
  au VimLeave * call s:vim_on_exit()
augroup end

function! s:vim_on_exit() abort
  if !exists('s:job_list')
    return
  endif

  for l:item in s:job_list
    let l:job_id = l:item['id']
    let l:status = s:job_status(l:job_id)
    if l:status ==# 'run'
      call s:job_stop(l:job_id)
    endif
  endfor
endfunction

"Check if current path is in blacklist
function! gen_tags#isblacklist(path) abort
  if !exists('g:gen_tags#blacklist') || g:gen_tags#blacklist == []
    call gen_tags#echo('blacklist not set or blacklist is null')
    return 0
  endif

  for l:dir in g:gen_tags#blacklist
    let l:dir = fnamemodify(gen_tags#fix_path(l:dir), ':p:h')
    if a:path ==# l:dir
      call gen_tags#echo('Found path ' . a:path . ' in the blacklist')
      return 1
    endif
  endfor

  call gen_tags#echo('Did NOT find path ' . a:path . ' in the blacklist')
  return 0
endfunction
