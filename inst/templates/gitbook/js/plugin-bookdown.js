require(["gitbook", "lodash"], function(gitbook, _) {

  var gs = gitbook.storage;

  gitbook.events.bind("start", function(e, config) {

    // add the Edit button (edit on Github)
    var edit = config.edit;
    if (edit && edit.link) gitbook.toolbar.createButton({
      icon: 'fa fa-edit',
      label: edit.text || 'Edit',
      position: 'left',
      onClick: function(e) {
        e.preventDefault();
        window.open(edit.link);
      }
    });

    var down = config.download;
    if (down) if (down.length === 1 && /[.]pdf$/.test(down[0])) {
      gitbook.toolbar.createButton({
        icon: 'fa fa-file-pdf-o',
        label: 'PDF',
        position: 'left',
        onClick: function(e) {
          e.preventDefault();
          window.open(down[0]);
        }
      });
    } else {
      gitbook.toolbar.createButton({
        icon: 'fa fa-download',
        label: 'Download',
        position: 'left',
        dropdown: $.map(down, function(link, i) {
          return {
            text: link.replace(/.*[.]/g, '').toUpperCase(),
            onClick: function(e) {
              e.preventDefault();
              window.open(link);
            }
          };
        })
      });
    }

    // highlight the current section in TOC
    var href = window.location.pathname;
    href = href.substr(href.lastIndexOf('/') + 1);
    if (href === '') href = 'index.html';
    var li = $('a[href^="' + href + location.hash + '"]').parent('li.chapter').first();
    li.addClass('active');
    var summary = $('ul.summary'), chaps = summary.find('li.chapter');
    chaps.on('click', function(e) {
      e.stopPropagation();
      chaps.removeClass('active');
      $(this).addClass('active');
      gs.set('tocScrollTop', summary.scrollTop());
    });

    var toc = config.toc;
    // collapse TOC items that are not for the current chapter
    if (toc && toc.collapse) (function() {
      var toc_sub = summary.children('li[data-level]').children('ul');
      toc_sub.hide().parent().has(li).children('ul').show();
      li.children('ul').show();
      var toc_sub2 = toc_sub.children('li');
      toc_sub2.children('ul').hide();
      toc_sub2.on('click.bookdown', function(e) {
        $(this).children('ul').toggle();
      });
    })();

    // add tooltips to the <a>'s that are truncated
    $('a').each(function(i, el) {
      if (el.offsetWidth >= el.scrollWidth) return;
      if (typeof el.title === 'undefined') return;
      el.title = el.text;
    });

    // restore TOC scroll position
    var pos = gs.get('tocScrollTop');
    if (typeof pos !== 'undefined') summary.scrollTop(pos);

    // highlight the TOC item that has same text as the heading in view as scrolling
    if (toc && toc.scroll_highlight !== false) (function() {
       // current chapter TOC items
      var items = $('a[href^="' + href + '"]').parent('li.chapter'),
          m = items.length;
      if (m === 0) return;
      // all section titles on current page
      var hs = bookInner.find('.page-inner').find('h1,h2,h3'), n = hs.length,
          ts = hs.map(function(i, el) { return el.innerText; });
      if (n === 0) return;
      bookInner.on('scroll.bookdown', function(e) {
        var ht = $(window).height();
        clearTimeout($.data(this, 'scrollTimer'));
        $.data(this, 'scrollTimer', setTimeout(function() {
          // find the first visible title in the viewport
          for (var i = 0; i < n; i++) {
            var rect = hs[i].getBoundingClientRect();
            if (rect.top >= 0 && rect.bottom <= ht) break;
          }
          if (i === n) return;
          items.removeClass('active');
          for (var j = 0; j < m; j++) {
            if (items.eq(j).children('a').first().text() === ts[i]) break;
          }
          if (j === m) j = 0;  // highlight the chapter title
          // search bottom-up for a visible TOC item to highlight; if an item is
          // hidden, we check if its parent is visible, and so on
          while (j > 0 && items.eq(j).is(':hidden')) j--;
          items.eq(j).addClass('active');
        }, 250));
      });
    })();

    var toolbar = config.toolbar;
    if (toolbar && toolbar.position === 'fixed') {
      var bookHeader = $('.book-header');
      bookHeader.addClass('fixed')
      .css('background-color', bookBody.css('background-color'))
      .on('click.bookdown', function(e) {
        // the theme may have changed after user clicks the theme button
        bookHeader.css('background-color', bookBody.css('background-color'));
      });
      bookBody.css('top', '50px');
    }

  });

  gitbook.events.bind("page.change", function(e) {
    // store TOC scroll position
    var summary = $('ul.summary');
    gs.set('tocScrollTop', summary.scrollTop());
  });

  var bookBody = $('.book-body'), bookInner = bookBody.find('.body-inner');
  $(document).on('servr:reload', function(e) {
    // save scroll position before page is reloaded via servr
    gs.set('bookBodyScrollTop',  bookBody.scrollTop());
    gs.set('bookInnerScrollTop', bookInner.scrollTop());
  });

  $(document).ready(function(e) {
    var pos1 = gs.get('bookBodyScrollTop');
    var pos2 = gs.get('bookInnerScrollTop');
    if (pos1) bookBody.scrollTop(pos1);
    if (pos2) bookInner.scrollTop(pos2);
    // clear book body scroll position
    gs.remove('bookBodyScrollTop');
    gs.remove('bookInnerScrollTop');
  });

});
