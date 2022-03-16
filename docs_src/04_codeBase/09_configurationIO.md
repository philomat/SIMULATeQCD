# Input and output formats for gauge configurations 

In lattice QCD calculations, there are several popular gauge configuration formats on the market.
These can differ in several ways, including how their header is implemented and how the to-be-saved
`Gaugefield` object is converted to binary. When deciding between ILDG and NERSC, note that
the ILDG takes up more storage space, since it's not compressed. The benefit of ILDG is that
it has more informative metadata and it allows one to store configurations on the Lattice
Data Grid.


## ILDG

The International Lattice Data Grid (ILDG) format has two main advantages, namely: 
1. The ILDG is the largest attempt by the lattice community to make gauge configurations 
generated by groups around the world publicly available, and we strive to be part of that 
community. If we would like to use their storage, we need to adhere to their format.
2. The ILDG format is perhaps the most descriptive (in the sense of metadata) and safe 
(in the sense of being sensitive to corrupted configurations) format available to the 
lattice community. More information about the ILDG effort can be found 
[here](https://hpc.desy.de/ildg/). You may also be interested in 
[this](https://www.sciencedirect.com/science/article/abs/pii/S0010465511000476) ILDG publication.

### How an ILDG configuration is packaged

A file saved in ILDG format format consists of several parts packaged using the 
Lattice QCD Interchange Message
Encapsulation (LIME) format. (You can learn more about LIME below.)
LIME files are organized as follows:
- One encapsulates ASCII or binary data into _records_.
- The records are packaged into _messages_. 

The `ildg-format` record is an XML document with some set of non-mutable parameters needed to 
read the binary. Here is an example:
```XML
<?xml version="1.0" encoding="UTF-8"?>
<ildgFormat xmlns="http://www.lqcd.org/ildg"
            xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
            xsi:schemaLocation="http://www.lqcd.org/ildg/filefmt.xsd">
  <version> 1.0 </version>
  <field> su3gauge </field>
  <precision> 32 </precision>
  <lx> 20 </lx> <ly> 20 </ly> <lz> 20 </lz> <lt> 64 </lt>
</ildgFormat>
```
The `ildg-binary-data` record is the stored binary data. It is a sequence of IEEE floating
point numbers. The precision is given in the `ildg-format` record. The endianness is big. 
In this format a `Gaugefield` is stored as an 8 (or 7) dimensional array of floating point
(or complex) numbers. The dimensions ordered from slowest to fastest running index are
1. site index $t$
2. site index $z$
3. site index $y$
4. site index $x$
5. direction index $\mu$
6. color index $a$
7. color index $b$
8. index indicating real (0) or imaginary (1) part 

The last entry is the `checksum`, which is a number characteristic of some binary data.
Two checksums are calculated for ILDG, both of which are extremely sensitive to changes
in the binary file; indeed if even a single bit is changed, the `checksum` changes.
By comparing the expected `checksum` saved in the header of an ILDG file with the
calculated `checksum` upon read in, one can tell whether the file has been corrupted.
 

### How a configuration is saved on the Lattice Data Grid

Once the ILDG configuration is packaged as a LIME file in the way specified above,
it is ready to be stored physically somewhere. This physical location where it
is stored is called the "Storage Element". If we want to write a script later to
find this saved configuration, the script needs to know where the configuration
is stored. Therefore for each ILDG file there is a corresponding XML file
stored in the QCDml configuration format. This XML file must validate against
the QCDml configuration schema given 
[here](https://www-zeuthen.desy.de/apewww/ILDG/specifications/QCDmlConfig1.3.1.xsd).
(To learn more about XML files and schemas, you can look
e.g. [here](https://www.w3schools.com/xml/).)

In addition to the location of the ILDG configuration, the QCDml file knows
a bunch of metadata about the configuration, like who made it and what
algorithm was used. 
This QCDml configuration file is then stored somewhere else, called
the "File Catalogue". Scripts that search for ILDG configurations will
interact with the File Catalogue. 

### How ILDG is implemented in SIMULATeQCD

One of the QCDml metadata is the location of the configuration on the Lattice
Data Grid, which is not known at the time of generation. Therefore there must
always be some post processing to get an ILDG configuration ready for storage.

With this in mind, what is implemented at the time of writing is this: Each
configuration made by SIMULATeQCD is a LIME file with the minimal amount
of information required for convenient reading by SIMULATeQCD, whose gauge
field is stored in binary according to the convention above. Since we can
read LIME format already, we are able to read arbitrary ILDG configurations.
However we cannot control how ILDG readers are implemented in other codes,
e.g. QUDA, so a configuration made by SIMULATeQCD will in general require
further processing to be readable by other codes.

### More about LIME

For detailed information about LIME, see its GitHub
project [here](https://github.com/usqcd-software/c-lime).
A LIME record is packed as follows:
1. A 144-byte header
2. The data (maximum of $2^{63}$ bytes)
3. Some null padding (0-7 bytes as needed)

The header is organized into 18 64-bit (8 byte) _words_ as follows:

| word | content|
|:----:|:-------|
|0     | subheader |
|1     | data length in bytes|
|2-17  | 128 byte LIME-type |

where the subheader consists of

| bits | content|
|:----:|:-------|
|0-31  | LIME magic number|
|32-47 | LIME file version number|
|48    | message begin bit|
|49    | message end bit|
|50-63 | reserved|

The `long int` LIME magic number, $1164413355_{10}=456789ab_{16}$, is used to identify
a record in LIME format. The version number is a `short int`. The three integer numbers in
the header, i.e. the magic number, version number, and data length, are written in
IEEE big-endian byte order for their data types, `long`, `short`, and
`long long`, respectively.

## NERSC

A NERSC format file consists of a simple header
```
BEGIN_HEADER
DATATYPE = 4D_SU3_GAUGE_3x3
DIMENSION_1 = 8
DIMENSION_2 = 8
DIMENSION_3 = 8
DIMENSION_4 = 4
CHECKSUM = 436aa5c1
LINK_TRACE = 0.002564709374
PLAQUETTE = 0.311637549
FLOATING_POINT = IEEE64BIG
END_HEADER
```
followed by the binary. The NERSC `checksum` is essentially a sum over all elements of
all links in the lattice. This `checksum` is not as sensitive as the ILDG checksum.

## MILC

MILC format is the format of the [MILC](https://github.com/milc-qcd/milc_qcd) code base.
As of v7.7.11, these binaries are always in single-precision.