# Smart Ontology Layer for Interoperable Systems (SOLIS)


## Getting started

Install the gem and add to the application's Gemfile by executing:

    $ bundle add solis

If bundler is not being used to manage dependencies, install the gem by executing:

    $ gem install solis

## Usage

Loading a SHACL file as an API

```ruby 
require 'solis'

shacl = %(
@prefix example: <https://example.com/>
@prefix xsd:    <http://www.w3.org/2001/XMLSchema#> .
@prefix sh:     <http://www.w3.org/ns/shacl#> .

example:CarShape 
        a sh:NodeShape;
        sh:description  "Abstract shape that describes a car entity" ;
        sh:targetClass  example:Car;
        sh:node         example:Car;
        sh:name         "Car";
        sh:property     [ sh:path        example:color;
                          sh:name        "color" ;
                          sh:description "Color of the car" ;
                          sh:datatype    xsd:string ;
                          sh:minCount    1 ;
                          sh:maxCount    1 ; ];
        sh:property     [ sh:path        example:brand;
                          sh:name        "brand" ;
                          sh:description "Brand of the car" ;
                          sh:datatype    xsd:string ;
                          sh:minCount    1 ;
                          sh:maxCount    1 ; ];
)


# load from car.ttl
solis = Solis.new(uri: 'file://car.ttl')

#load from StringIO object
solis = Solis.new(io: StringIO.new(shacl), content_type: 'text/turtle')

#load from File object
solis = Solis.new(io: File.open('car.ttl'), content_type: 'text/turtle')

#load from Google Sheet
solis = Solis.new(uri: 'google+sheet://18JDgCfr2CLl_jATuvFTcpu-a5T6CWAgJwTwEqtSe8YE')

```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/solis. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/[USERNAME]/solis/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Solis project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/[USERNAME]/solis/blob/master/CODE_OF_CONDUCT.md).





## Accelerating API Development Using SHACL-Driven Smart Layers on Triple Stores

### Abstract
The development of APIs for business applications often involves translating conceptual data models into functional interfaces. This process can be time-consuming and depends heavily on the clarity of business requirements and the technical expertise available. In this paper, we propose a methodology to streamline this transition by leveraging SHACL (Shapes Constraint Language) as a schema description tool for triple stores. By automating the creation of APIs from SHACL-defined models, we aim to reduce development time and complexity, while enhancing the accessibility of linked data technologies for developers.

### Introduction
Designing robust data models requires a deep understanding of the business domain, while building functional interfaces atop these models demands technological proficiency. Bridging the gap between business needs and technical implementation often poses challenges, particularly when business processes are still evolving. The time required to transform an idea into a developer-ready API depends on the clarity and finality of these processes.

To address these challenges, tools that accelerate the transition from data model to API are invaluable. In this study, we outline a general approach for describing business models, generating corresponding SHACL files, and using these files to automate API creation. The backend for this system is a triple store, which provides a flexible and scalable foundation for data storage and retrieval.

### What is a Triple Store?
A triple store is a type of database optimized for storing and querying linked data. Conceptually, it can be compared to a key-value store, where the key is split into a subject and predicate (akin to an identifier and property name in relational databases). Unlike traditional databases, triple stores lack predefined table structures and constraints, relying instead on standards such as RDF and SHACL for organization and validation.

While this flexibility is powerful, it can also make triple stores daunting for developers unfamiliar with linked data paradigms. Many perceive the added complexity as a barrier, with little immediate benefit to justify the learning curve. To address this, our approach emphasizes the creation of user-friendly APIs that abstract the underlying complexity, ensuring seamless validation and database communication.

### Methodology

### 1. Describing the Model
A model is a representation of the knowledge within a business domain. It serves various purposes, including documentation, data validation, and, in our case, API generation. While numerous methods exist for model description, we focus on the use of spreadsheets due to their simplicity and accessibility.

The model description is divided into namespaces, entities, properties, and relationships. Each namespace is documented in a spreadsheet, with specific sheets dedicated to metadata, data types, prefixes, and references. Entities are defined in an _ENTITIES sheet, which specifies attributes such as entity names, plural forms, and inheritance relationships (e.g., subClassOf or sameAs).

### 2. Generating the SHACL File
The spreadsheet-based model description is converted into a SHACL file. This file serves as the schema for the triple store, defining constraints and shapes for data validation.

### 3. Creating the API
Using the SHACL file, an automated process generates an API that interacts with the triple store. The API abstracts the complexities of linked data, providing developers with a straightforward interface for building applications.

### Results
By implementing this methodology, we demonstrate significant reductions in the time and effort required to transition from a conceptual model to a functional API. The spreadsheet-based approach simplifies model creation, while the automated SHACL-to-API pipeline minimizes manual intervention.

### Conclusion
The integration of SHACL and triple stores offers a powerful solution for accelerating API development. By bridging the gap between business and technology, this approach empowers organizations to rapidly deploy data-driven applications while maintaining the flexibility and rigor of linked data standards. Future work will focus on refining the tooling and exploring additional use cases for this methodology.
