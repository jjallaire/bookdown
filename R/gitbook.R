#' The GitBook output format
#'
#' This output format function ported a style provided by GitBook
#' (\url{https://www.gitbook.com}) for R Markdown.
#' @inheritParams html_chapters
#' @param fig_caption,lib_dir,... Arguments to be passed to
#'   \code{rmarkdown::\link{html_document}()} (\code{...} not including
#'   \code{toc}, \code{number_sections}, \code{self_contained}, \code{theme},
#'   and \code{template}).
#' @param config A list of configuration options for the gitbook style, such as
#'   the font/theme settings.
#' @note The default value of the argument \code{html_names} is
#'   \code{'section+number'}, but it is set to \code{'rmd'} of this function is
#'   called in the RStudio IDE. If you want it to be other values, you can
#'   specify this argument \emph{explicitly}, e.g. \code{gitbook(html_names =
#'   'section+number')} (or set it in the YAML frontmatter).
#' @export
gitbook = function(
  fig_caption = TRUE, lib_dir = 'libs', ...,
  html_names = c('section+number', 'section', 'chapter+number', 'chapter', 'rmd', 'none'),
  config = list()
) {
  html_document2 = function(..., extra_dependencies = list()) {
    rmarkdown::html_document(
      ..., extra_dependencies = c(extra_dependencies, gitbook_dependency())
    )
  }
  gb_config = config
  config = html_document2(
    toc = TRUE, number_sections = TRUE, fig_caption = fig_caption,
    self_contained = FALSE, lib_dir = lib_dir, theme = NULL,
    template = bookdown_file('templates', 'gitbook.html'), ...
  )
  # use Rmd filenames = TRUE by default if called in RStudio
  html_names = if (missing(html_names) && !is.na(Sys.getenv('RSTUDIO', NA)))
    'rmd' else match.arg(html_names)
  post = config$post_processor  # in case a post processor have been defined
  config$post_processor = function(metadata, input, output, clean, verbose) {
    if (is.function(post)) output = post(metadata, input, output, clean, verbose)
    on.exit(write_search_data(), add = TRUE)
    move_files_html(output, lib_dir)
    split_chapters(
      output, gitbook_page, html_names, gb_config, html_names
    )
  }
  config$bookdown_output_format = 'html'
  config = set_opts_knit(config)
  config
}

gitbook_search = local({
  data = NULL
  list(
    get = function() data,
    collect = function(...) data <<- c(data, ...),
    empty = function() data <<- NULL
  )
})

write_search_data = function(x) {
  x = gitbook_search$get()
  if (length(x) == 0) return()
  gitbook_search$empty()
  x = matrix(strip_html(x), nrow = 3)
  x = apply(x, 2, json_string, toArray = TRUE)
  x = paste0('[\n', paste0(x, collapse = ',\n'), '\n]')
  writeUTF8(x, output_path('search_index.json'))
}

gitbook_dependency = function() {
  assets = bookdown_file('templates', 'gitbook')
  owd = setwd(assets); on.exit(setwd(owd), add = TRUE)
  list(htmltools::htmlDependency(
    'gitbook', '2.6.7', src = assets,
    stylesheet = file.path('css', c(
      'style.css', 'plugin-highlight.css', 'plugin-search.css',
      'plugin-fontsettings.css'
    )),
    script = file.path('js', c(
      'app.js', 'lunr.js', 'plugin-search.js', 'plugin-sharing.js',
      'plugin-fontsettings.js', 'plugin-bookdown.js'
    ))
  ))
}

gitbook_page = function(
  head, toc, chapter, link_prev, link_next, rmd_cur, html_cur, foot,
  config, html_names
) {
  toc = gitbook_toc(toc, rmd_cur, config[['toc']])

  has_prev = length(link_prev) > 0
  has_next = length(link_next) > 0
  a_prev = if (has_prev) sprintf(
    '<a href="%s" class="navigation navigation-prev %s" aria-label="Previous page"><i class="fa fa-angle-left"></i></a>',
    link_prev, if (has_next) '' else 'navigation-unique'
  ) else ''
  a_next = if (has_next) sprintf(
    '<a href="%s" class="navigation navigation-next %s" aria-label="Next page""><i class="fa fa-angle-right"></i></a>',
    link_next, if (has_prev) '' else 'navigation-unique'
  ) else ''
  foot = sub('<!--bookdown:link_prev-->', a_prev, foot)
  foot = sub('<!--bookdown:link_next-->', a_next, foot)

  l_prev = if (has_prev) sprintf('<link rel="prev" href="%s">', link_prev) else ''
  l_next = if (has_next) sprintf('<link rel="next" href="%s">', link_next) else ''
  head = sub('<!--bookdown:link_prev-->', l_prev, head)
  head = sub('<!--bookdown:link_next-->', l_next, head)

  # gitbook JS scripts only work after the DOM has been loaded, so move them
  # from head to foot
  i = grep('^\\s*<script src=".+/gitbook([^/]+)?/js/[a-z-]+[.]js"></script>\\s*$', head)
  s = head[i]; head[i] = ''
  j = grep('<!--bookdown:config-->', foot)[1]
  foot[j] = paste(c(s, foot[j]), collapse = '\n')

  titles = paste(grep('^<(h[12])(>| ).+</\\1>.*$', chapter, value = TRUE), collapse = ' ')
  gitbook_search$collect(html_cur, titles, paste(chapter, collapse = ' '))

  # you can set the edit setting in either _bookdown.yml or _output.yml
  if (is.list(setting <- edit_setting())) config$edit = setting
  if (length(rmd_cur)) config$edit$link = sprintf(config$edit$link, rmd_cur)

  if (length(exts <- load_config()[['download']]) == 0) exts = config$download
  if (length(exts)) config$download = I(with_ext(opts$get('book_filename'), paste0('.', exts)))

  foot = sub('<!--bookdown:config-->', gitbook_config(config), foot)

  c(head, toc, chapter, foot)
}

gitbook_toc = function(x, cur, config) {
  i1 = find_token(x, '<!--bookdown:toc2:start-->')
  i2 = find_token(x, '<!--bookdown:toc2:end-->')
  x[i1] = ''; x[i2] = ''
  if (i2 - i1 < 2) return(x)
  toc = x[(i1 + 1):(i2 - 1)]
  if (toc[1] == '<ul>') {
    toc[1] = '<ul class="summary">'
    if (!is.null(extra <- config[['before']])) {
      toc[1] = paste(c(toc[1], extra, '<li class="divider"></li>'), collapse = '\n')
    }
  }
  n = length(toc)
  if (toc[n] == '</ul>') {
    if (!is.null(extra <- config[['after']])) {
      toc[n] = paste(c('<li class="divider"></li>', extra, toc[n]), collapse = '\n')
    }
  }
  r = '^<li><a href="([^#]*)(#[^"]+)"><span class="toc-section-number">([0-9.]+)</span>([^<]+)(</a>.*)$'
  i = grep(r, toc)
  toc[i] = gsub(
    r,
    '<li class="chapter" data-level="\\3" data-path="\\1"><a href="\\1\\2"><i class="fa fa-check"></i><b>\\3</b>\\4\\5',
    toc[i]
  )
  toc[i] = sub(' data-path="">', paste0(' data-path="', with_ext(cur, '.html'), '">'), toc[i])
  r = '^<li><a href="([^#]*)(#[^"]+)">([^<]+</a>.*)$'
  i = grep(r, toc)
  toc[i] = gsub(
    r,
    '<li class="chapter" data-level="" data-path="\\1"><a href="\\1\\2"><i class="fa fa-check"></i>\\3',
    toc[i]
  )
  if (isTRUE(config[['collapse']])) {
    r = '^<li .+ data-level="([^.]+)?" .+>.+</a><ul>$'
    i = grep(r, toc)
    toc[i] = gsub('<ul>$', '<ul style="display:none;">', toc[i])
  }
  x[(i1 + 1):(i2 - 1)] = toc
  x
}

gitbook_toc_extra = function(which = c('before', 'after')) {
  which = match.arg(which)
  config = load_config()
  config[[sprintf('gitbook_toc_%s', which)]]
}

gitbook_config = function(config = list()) {
  default = list(
    sharing = list(
      facebook = TRUE, twitter = TRUE, google = FALSE, weibo = FALSE,
      instapper = FALSE, vk = FALSE,
      all = c('facebook', 'google', 'twitter', 'weibo', 'instapaper')
    ),
    fontsettings = list(theme = 'white', family = 'sans', size = 2),
    edit = list(link = NULL, text = NULL),
    download = NULL
    # toolbar = list(position = 'fixed'),
    # toc = list(collapse = TRUE)
  )
  config = utils::modifyList(default, config, keep.null = TRUE)
  # remove these TOC config items since we don't need them in JavaScript
  config$toc$before = NULL; config$toc$after = NULL
  config = sprintf('gitbook.start(%s);', tojson(config))
  paste(
    '<script>', 'require(["gitbook"], function(gitbook) {', config, '});',
    '</script>', sep = '\n'
  )
}
