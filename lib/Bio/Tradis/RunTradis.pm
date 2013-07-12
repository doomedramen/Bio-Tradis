package Bio::Tradis::RunTradis;

# ABSTRACT: Perform all steps required for a tradis analysis

=head1 SYNOPSIS

Takes a fastq file with tags already attached, filters the tags matching user input,
removes the tags, maps to a reference (.fa) and generates insertion site plots for use in
Artemis

   use Bio::Tradis::RunTradis;
   
   my $pipeline = Bio::Tradis::RunTradis->new(
					fastqfile => 'abc',  
					reference => 'abc',
					tag => 'abc',
					tagdirection => '5'|'3'
   );
   $pipeline->run_tradis();

=cut

use Moose;
use File::Temp;
use Bio::Tradis::FilterTags;
use Bio::Tradis::RemoveTags;
use Bio::Tradis::Map;
use Bio::Tradis::TradisPlot;

has 'fastqfile' => ( is => 'rw', isa => 'Str', required => 1 );
has 'tag'       => ( is => 'ro', isa => 'Str', required => 1 );
has 'tagdirection' =>
  ( is => 'ro', isa => 'Str', required => 1, default => '5' );
has 'mismatch' => ( is => 'rw', isa => 'Int', required => 1 );
has 'mapping_score' =>
  ( is => 'ro', isa => 'Int', required => 1, default => 30 );
has 'reference' => ( is => 'rw', isa => 'Str', required => 1 );
has 'outfile' => (
    is       => 'rw',
    isa      => 'Str',
    required => 0,
    default  => sub {
        my ($self) = @_;
        my @dirs = split( '/', $self->fastqfile );
        my $o = pop(@dirs);
        $o =~ s/fastq/out/;
        return $o;
    }
);
has '_destination' => (
    is       => 'rw',
    isa      => 'File::Temp::Dir',
    required => 0,
    lazy     => 1,
    builder  => '_build__destination'
);
has '_stats_handle' => (
    is       => 'ro',
    isa      => 'FileHandle',
    required => 0,
    lazy     => 1,
    builder  => '_build__stats_handle'
);
has '_plotfile' => (
    is       => 'rw',
    isa      => 'Str',
    required => 0,
    lazy     => 1,
    builder  => '_build__plotfile'
);
has '_sequence_name' => (
    is       => 'rw',
    isa      => 'Str',
    required => 0,
    lazy     => 1,
    builder  => '_build__sequence_name'
);
has '_current_directory' => (
    is       => 'rw',
    isa      => 'Str',
    required => 0,
    lazy     => 1,
    builder  => '_build__current_directory'
);

sub _build__stats_handle {
    my ($self) = @_;
    my $outfile = $self->outfile;

    open( my $stats, ">", "$outfile.stats" );
    return $stats;
}

sub _build__plotfile {
    my ($self)                = @_;
    my $destination_directory = $self->_destination->dirname;
    my $outfile               = $self->outfile;

    my $seqname       = $self->_sequence_name;
    my $plotfile_name = "$outfile.$seqname.insert_site_plot.gz";
    return $plotfile_name;
}

sub _build__sequence_name {
    my ($self) = @_;
    my $destination_directory = $self->_destination->dirname;

    my $sn =
`grep \@SQ $destination_directory/mapped.sam | awk '{print \$2}' | sed s/SN://`;
    chomp($sn);
    return $sn;
}

sub _build__destination {
    return File::Temp->newdir( CLEANUP => 0 );
}

sub _build__current_directory {
    my ($self) = @_;
    my $fq = $self->fastqfile;

    my @dirs = split( '/', $fq );
    pop(@dirs);
    return join( '/', @dirs );
}

sub run_tradis {
    my ($self) = @_;
    my $destination_directory = $self->_destination->dirname();

    # Step 1: Filter tags that match user input tag
    print STDERR "..........Step 1: Filter tags that match user input tag\n";
    $self->_filter;

    `ls $destination_directory`;

    # Step 2: Remove the tag from the sequence and quality strings
    print STDERR
"..........Step 2: Remove the tag from the sequence and quality strings\n";
    $self->_remove;

    `ls $destination_directory`;

    # Step 3: Map file to reference
    print STDERR "..........Step 3: Map file to reference\n";
    $self->_map;

    `ls $destination_directory`;

    # Step 3.5: Convert output from SAM to BAM and sort
    print STDERR
      "..........Step 3.5: Convert output from SAM to BAM and sort\n";
    $self->_sam2bam;
    $self->_sort_bam;

    `ls $destination_directory`;

    # Step 4: Generate plot
    print STDERR "..........Step 4: Generate plot\n";
    $self->_make_plot;

    `ls $destination_directory`;

    # Step 5: Generate statistics
    print STDERR "..........Step 5: Generate statistics\n";
    $self->_stats;

    `ls $destination_directory`;

    # Step 6: Move files to current directory
    print STDERR "..........Step 6: Move files to current directory\n";
    my $outfile = $self->outfile;
    system("mv $destination_directory/$outfile* \.");

    # Clean up
    print("..........Clean up\n");
    unlink("$destination_directory/filter.fastq");
    unlink("$destination_directory/tags_removed.fastq");
    unlink("$destination_directory/mapped.sam");
    unlink("$destination_directory/ref.index.sma");
    unlink("$destination_directory/ref.index.smi");
    unlink("$destination_directory/mapped.bam");
    unlink("$destination_directory/tmp.plot");
    File::Temp::cleanup();

    return 1;
}

sub _filter {
    my ($self)                = @_;
    my $destination_directory = $self->_destination->dirname;
    my $fqfile                = $self->fastqfile;
    my $tag                   = $self->tag;

    my $filter = Bio::Tradis::FilterTags->new(
        fastqfile => $fqfile,
        tag       => $tag,
		mismatch => $self->mismatch,
        outfile   => "$destination_directory/filter.fastq"
    )->filter_tags;
}

sub _remove {
    my ($self)                = @_;
    my $destination_directory = $self->_destination->dirname;
    my $tag                   = $self->tag;

    my $rm_tags = Bio::Tradis::RemoveTags->new(
        fastqfile => "$destination_directory/filter.fastq",
        tag       => $tag,
		mismatch => $self->mismatch,
        outfile   => "$destination_directory/tags_removed.fastq"
    )->remove_tags;
}

sub _map {
    my ($self)                = @_;
    my $destination_directory = $self->_destination->dirname;
    my $ref                   = $self->reference;

    my $mapping = Bio::Tradis::Map->new(
        fastqfile => "$destination_directory/tags_removed.fastq",
        reference => "$ref",
        refname   => "$destination_directory/ref.index",
        outfile   => "$destination_directory/mapped.sam"
    );
    $mapping->index_ref;
    $mapping->do_mapping;
}

sub _sam2bam {
    my ($self) = @_;
    my $destination_directory = $self->_destination->dirname;

    system(
"samtools view -b -o $destination_directory/mapped.bam -S $destination_directory/mapped.sam"
    );
    return 1;
}

sub _sort_bam {
    my ($self) = @_;
    my $destination_directory = $self->_destination->dirname;

    system(
"samtools sort $destination_directory/mapped.bam $destination_directory/mapped.sort"
    );
    return 1;
}

sub _make_plot {
    my ($self)                = @_;
    my $destination_directory = $self->_destination->dirname;
    my $ref                   = $self->reference;
    my $outfile               = $self->outfile;
    my $tr_d                  = $self->tagdirection;

    my $plot = Bio::Tradis::TradisPlot->new(
        mappedfile    => "$destination_directory/mapped.sort.bam",
        reference     => "$ref",
        mapping_score => $self->mapping_score,
        outfile       => "$destination_directory/$outfile"
    )->plot;

    # if tag direction is 5, reverse plot columns
    if ( $self->tagdirection eq '5' ) {
        $self->_reverse_plot;
    }
}

sub _reverse_plot {
    my ($self)                = @_;
    my $destination_directory = $self->_destination->dirname;
    my $outfile               = $self->outfile;

    my $plotname = $self->_plotfile;
    system("gunzip -c $plotname > $destination_directory/tmp.plot");
    system(
"awk '{ t = \$1; \$1 = \$2; \$2 = t; print; }' $destination_directory/tmp.plot > rv_plot"
    );
    system("gzip -c rv_plot > $plotname");

    unlink("$destination_directory/tmp.plot");
    unlink("rv_plot");
}

sub _stats {
    my ($self)                = @_;
    my $outfile               = $self->outfile;
    my $destination_directory = $self->_destination->dirname;
    my $fq                    = $self->fastqfile;
    my $plotname              = $self->_plotfile;
    my @fields                = (
        "File",
        "Total Reads",
        "Reads Matched",
        "\% Matched",
        "Reads Mapped",
        "\% Mapped",
        "Unique Insertion Sites"
    );
    my $stats = join( "\t", @fields ) . "\n";

    # Add file name and number of reads in it
    $stats .= "$self->fastqfile\t";
    my $total_reads = `grep -c "^\@" $fq`;
    chomp($total_reads);
    $stats .= "$total_reads\t";

    # Matching reads
    my $matching = `grep -c "^\@" $destination_directory/filter.fastq`;
    chomp($matching);
    $stats .= "$matching\t";
    $stats .= ( $matching / $total_reads ) * 100 . "\t";

    # Mapped reads
    my $mapped = `grep -v -c ^\@ $destination_directory/mapped.sam`;
    chomp($mapped);
    $stats .= "$mapped\n";
    $stats .= ( $mapped / $matching ) * 100 . "\t";

    # Unique insertion sites
    system(
"gunzip -c $destination_directory/$plotname > $destination_directory/tmp.plot"
    );
    my $uis =
`grep -v "^0" $destination_directory/tmp.plot | sort | uniq | wc | awk '{ print \$1 }'`;
    $stats .= "$uis\n";

    print { $self->_stats_handle } $stats;
}

__PACKAGE__->meta->make_immutable;
no Moose;
1;
