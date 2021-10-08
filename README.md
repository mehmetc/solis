# Solis

Solis might mean 'the sun' in Latin or just Silos spelled backwards. It is an attempt to use a SHACL file as a description for an API on top of a data store.


TODO:
 - extract sparql layer into its own gem

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'solis'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install solis

## Usage

Transforming a Google Sheet into a SHACL file and Entity model.

[Google sheet template](https://docs.google.com/spreadsheets/d/1vi2U9Gpgu9mA6OpvrDBWRg8oVKs6Es63VyLDIKFNWYM/edit?usp=drive_web&ouid=105856802847127219255) example

Tabs starting with an underscore define general metadata 
    - _PREFIXES: ontologies to include in SHACL file
    - _METADATA: key/value pairs describing the ontology
    - _ENTITIES: a list of entities describing if it is a sub class of or same as an external entity

Every entity that is referenced in _ENTITIES can be further described in its own tab.




TODO: Write usage instructions here

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/solis. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/[USERNAME]/solis/blob/master/CODE_OF_CONDUCT.md).


## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Solis project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/[USERNAME]/solis/blob/master/CODE_OF_CONDUCT.md).
