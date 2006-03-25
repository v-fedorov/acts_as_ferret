require File.dirname(__FILE__) + '/../test_helper'

class ContentTest < Test::Unit::TestCase
  include Ferret::Index
  include Ferret::Search
  fixtures :contents, :comments

  def setup
    @content = Content.new( :title => 'My Title', :description => 'A useless description' )
    @content.save
    @another_content = Content.new( :title => 'Another Content item', 
                                    :description => 'this is not the title' )
    @another_content.save
    @comment = Comment.new( :author => 'john doe', :content => 'This is a useless comment' )
    @comment.save
    @comment2 = Comment.new( :author => 'another', :content => 'content' )
    @comment2.save

    @another_content.comments << @comment
    @another_content.comments << @comment2
    @another_content.save
  end
  
  def teardown
    @content.destroy if @content
    @another_content.destroy if @another_content
    @comment.destroy if @comment
    @comment2.destroy if @comment2
  end
  
  def test_truth
    assert_kind_of Content, contents(:first)
  end

  def test_class_index_dir
    assert_equal "#{RAILS_ROOT}/index/test/Content", Content.class_index_dir
  end

  def test_indexed_method
    assert_equal 2, @another_content.comments.size
    # retrieve all content objects having more than 1 comments
    result = Content.find_by_contents('comment_count:[2 TO 1000]')
    assert_equal 1, result.size
    assert_equal @another_content.id, result.first.id
  end

  def test_multi_index
    i =  FerretMixin::Acts::ARFerret::MultiIndex.new([Content, Comment])
    hits = i.search(TermQuery.new(Term.new("title","title")))
    assert_equal 1, hits.score_docs.size

    qp = Ferret::QueryParser.new("title", 
                      :analyzer => Ferret::Analysis::WhiteSpaceAnalyzer.new)
    hits = i.search(qp.parse("title"))
    assert_equal 1, hits.score_docs.size
    
    qp = Ferret::QueryParser.new("*", 
                      :analyzer => Ferret::Analysis::WhiteSpaceAnalyzer.new)
    qp.fields = i.reader.get_field_names.to_a
    hits = i.search(qp.parse("title"))
    assert_equal 2, hits.score_docs.size

    hits = i.search("title")
    assert_equal 2, hits.score_docs.size
    
    hits = i.search("title OR comment")
    assert_equal 5, hits.score_docs.size
  end

  def test_multi_reader
    r = MultiReader.new([IndexReader.open(Content.class_index_dir), IndexReader.open(Comment.class_index_dir)])
    s = IndexSearcher.new(r)
    hits = s.search(TermQuery.new(Term.new("title","title")))
    assert_equal 1, hits.score_docs.size
  end
    
  def test_multi_search
    assert_equal 4, Content.find(:all).size
    contents_from_ferret = Content.multi_search('*:title')
    assert_equal 2, contents_from_ferret.size
    assert_equal @content.id, contents_from_ferret.first.id
    assert_equal @another_content.id, contents_from_ferret.last.id
    
    contents_from_ferret = Content.multi_search('title OR comment', [Comment])
    assert_equal 5, contents_from_ferret.size
  end

  def test_id_multi_search
    assert_equal 4, Content.find(:all).size
    contents_from_ferret = Content.id_multi_search('*:title')
    assert_equal 2, contents_from_ferret.size
    assert_equal @content.id, contents_from_ferret.first[:id].to_i
    assert_equal @another_content.id, contents_from_ferret.last[:id].to_i
    
    contents_from_ferret = Content.id_multi_search('title OR comment', [Comment])
    assert_equal 5, contents_from_ferret.size
  end

  def test_find_by_contents

    contents_from_ferret = Content.find_by_contents('title')
    assert_equal 2, contents_from_ferret.size
    # the title field has a higher boost value, so @content must be first in the list
    assert_equal @content.id, contents_from_ferret.first.id 
    assert_equal @another_content.id, contents_from_ferret.last.id
    
    # limit result set size to 1
    contents_from_ferret = Content.find_by_contents('title', :num_docs => 1)
    assert_equal 1, contents_from_ferret.size
    assert_equal @content.id, contents_from_ferret.first.id 
    
    # limit result set size to 1, starting with the second result
    contents_from_ferret = Content.find_by_contents('title', :num_docs => 1, :first_doc => 1)
    assert_equal 1, contents_from_ferret.size
    assert_equal @another_content.id, contents_from_ferret.first.id 
     

    contents_from_ferret = Content.find_by_contents('useless')
    assert_equal 1, contents_from_ferret.size
    assert_equal @content.id, contents_from_ferret.first.id
    
    # no monkeys here
    contents_from_ferret = Content.find_by_contents('monkey')
    assert contents_from_ferret.empty?
    
    # multiple terms are ANDed by default...
    contents_from_ferret = Content.find_by_contents('monkey description')
    assert contents_from_ferret.empty?
    # ...unless you connect them by OR
    contents_from_ferret = Content.find_by_contents('monkey OR description')
    assert_equal 1, contents_from_ferret.size
    assert_equal @content.id, contents_from_ferret.first.id

    # multiple terms, each term has to occur in a document to be found, 
    # but they may occur in different fields
    contents_from_ferret = Content.find_by_contents('useless title')
    assert_equal 1, contents_from_ferret.size
    assert_equal @content.id, contents_from_ferret.first.id
    

    # search for an exact string by enclosing it in "
    contents_from_ferret = Content.find_by_contents('"useless title"')
    assert contents_from_ferret.empty?
    contents_from_ferret = Content.find_by_contents('"useless description"')
    assert_equal 1, contents_from_ferret.size
    assert_equal @content.id, contents_from_ferret.first.id

    # wildcard query
    contents_from_ferret = Content.find_by_contents('use*')
    assert_equal 1, contents_from_ferret.size

    # ferret-bug ? wildcard queries don't seem to get lowercased even when
    # using StandardAnalyzer:
    # contents_from_ferret = Content.find_by_contents('Ti*')
    # we should find both 'Title' and 'title'
    # assert_equal 2, contents_from_ferret.size 
    # theory: :wild_lower parser option isn't used

    contents_from_ferret = Content.find_by_contents('ti*')
    # this time we find both 'Title' and 'title'
    assert_equal 2, contents_from_ferret.size

    @content.destroy
    contents_from_ferret = Content.find_by_contents('ti*')
    # should find only one now
    assert_equal 1, contents_from_ferret.size
    assert_equal @another_content.id, contents_from_ferret.first.id
   end

   def test_find_by_contents_options
     
   end
end
