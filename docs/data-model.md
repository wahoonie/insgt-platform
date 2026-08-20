# Data Model

## Core Entities

### Order

An Order is the central entity in the system. It represents a scheduled service provided at a property for a real estate agent.

Orders produce media — photos, videos, Matterports, Zillow 3D virtual tours, and floor plans. Because photographers have different specializations, a single property visit often requires multiple orders. Photographer A shoots interiors at 2pm, Photographer B flies aerials at 3pm, Photographer C returns at 7pm for twilight photos.

These related orders are grouped using a parent/child relationship. The parent order represents the overall job for the property. Each child order represents a specific service assignment for a specific photographer. A standalone order with no children is both the parent and the job.

### Photo

Photos are the primary media type produced by the system. Most orders result in a set of photos that go through processing (HDR tone mapping, color correction, sky replacement, etc.) before delivery to the client.

With the introduction of California law AB 723, the system also tracks **UnalteredPhotos**. An UnalteredPhoto is the version of a photo before any enhancements that would trigger disclosure requirements. A Photo can optionally have one associated UnalteredPhoto. When the UnalteredPhoto exists, both versions are made available to customers — the enhanced version for marketing use (with required disclosures) and the unaltered version for use without disclosure obligations.

Not all processing triggers AB 723. Standard adjustments like exposure correction and HDR tone mapping do not require disclosure. Only material alterations — sky replacement, object removal, virtual staging — create the need for an UnalteredPhoto record.

### Listing

A Listing is a supplementary entity built around an Order and its children. It connects property data from an external MLS API, caches it locally, and makes it available to services like insgt-virtual-tour. A listing has one order assigned to it, and then when pulling in media for the listing it starts at the parent and then pulls in all additional media from the children.

This allows customers to receive a public virtual tour URL they can submit to the MLS, combining our produced media with live listing data (price, beds/baths, description, agent info).

### Accounts

Accounts are the organizing principle for users of the system. Each account has multiple users assigned to the account with different roles.

Accounts are used for the internal team consisting of sytem admins, system photographers, system processors.

Accounts are also used for customers who can have multiple people on a team. This corresponds to real estate agents who have their own agent teams with a primary agent, an accountant, a marketer, etc.

Because agents like to work together often, you can also see users that belong to multiple accounts.

For example Agent A belongs to their own Account A as an owner. Agent B belongs to their own Account B as an owner. Agent A and Agent B both belong to Account C as members. This is most often seen when agents have a shared listing and they want both of their informaiton to appear in the listing.


## Entity Relationships

```
Order (parent)
├── Order (child: interior photos)
│   ├── Photo → UnalteredPhoto (optional)
│   ├── Photo → UnalteredPhoto (optional)
│   └── Photo
├── Order (child: aerials)
│   ├── Photo → UnalteredPhoto (optional)
│   └── Photo
├── Order (child: twilight)
│   └── Photo → UnalteredPhoto (optional)
└── Listing
    └── MLS Data (cached from external API)
```

## Key Concepts

**Parent/Child Orders**: The parent is what the client sees as "the job." Children are how the system manages scheduling, photographer assignment, and service-specific workflows. Client-facing features (galleries, downloads, virtual tours) typically operate at the parent level, aggregating media from all children.

**AB 723 Compliance**: The presence or absence of an UnalteredPhoto on a Photo record is what drives disclosure logic throughout the system — download options, gallery labels, and MLS-ready packaging all key off this relationship.

**Listing as an Add-On**: Not every Order has a Listing. It's an optional service layer. When present, it enriches the order's media with property context, enabling features like virtual tours that combine photography with real estate data.
