package Bio::Tradis::TradisPlot;

# ABSTRACT: Generate plots as part of a tradis analysis

=head1 SYNOPSIS

Generate insertion plots for Artemis from a mapped fastq file and a reference
in GFF format

   use Bio::Tradis::TradisPlot;
   
   my $pipeline = Bio::Tradis::TradisPlot->new(mappedfile => 'abc');
   $pipeline->plot();

=cut

use Moose;

has 'mappedfile' => ( is => 'rw', isa => 'Str', required => 1 );
has 'outfile'    => ( is => 'rw', isa => 'Str', required => 0 );

sub plot {
    my ($self) = @_;

	Bio::Tradis::Analysis::InsertSite->new(
	    filename             => $mappedfile,
	    output_base_filename => $outfile
	)->create_plots();

    return 1;
}

__PACKAGE__->meta->make_immutable;
no Moose;
1;
